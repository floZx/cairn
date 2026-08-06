import Foundation
import SwiftData

/// Abstracts the network away from the engine so a sync can be tested end to
/// end without HTTP.
protocol ActivitySource: Sendable {
    func activities(after: Int, page: Int, perPage: Int) async throws -> [SummaryActivityDTO]
    func streams(id: Int64) async throws -> StreamSetDTO
    func activityDetail(id: Int64) async throws -> DetailActivityDTO
    func athlete() async throws -> AthleteDTO
    func gear(id: String) async throws -> GearDTO
    func rateLimitSnapshot() async -> RateLimitSnapshot?
}

/// `StravaClient` already has every one of these signatures, so the conformance
/// needs no bridging methods — adding one here would just recurse.
extension StravaClient: ActivitySource {}

/// An immutable copy of the sync progress, safe to hand outside the engine.
///
/// `SyncState` itself is a SwiftData `@Model` bound to the engine's private
/// `ModelContext`, so it must never cross an isolation boundary.
struct SyncStateSnapshot: Sendable, Equatable {
    var lastSummaryEpoch: Int
    var pendingStreamIDs: [Int64]
    var lastRunAt: Date?
    var lastErrorMessage: String?
    var isInitialImportDone: Bool
}

actor SyncEngine {
    private let source: ActivitySource
    private let container: ModelContainer
    private let progress: SyncProgress
    private let context: ModelContext
    private let mapper: ImportMapper

    private static let pageSize = 200

    init(source: ActivitySource, container: ModelContainer, progress: SyncProgress) {
        self.source = source
        self.container = container
        self.progress = progress
        let context = ModelContext(container)
        self.context = context
        self.mapper = ImportMapper(context: context)
    }

    /// Single-row sync state, created on first access.
    private func state() throws -> SyncState {
        if let existing = try context.fetch(FetchDescriptor<SyncState>()).first {
            return existing
        }
        let created = SyncState()
        context.insert(created)
        try context.save()
        return created
    }

    /// The progress record as a value, for callers outside the actor.
    func stateSnapshot() throws -> SyncStateSnapshot {
        let state = try state()
        return SyncStateSnapshot(
            lastSummaryEpoch: state.lastSummaryEpoch,
            pendingStreamIDs: state.pendingStreamIDs,
            lastRunAt: state.lastRunAt,
            lastErrorMessage: state.lastErrorMessage,
            isInitialImportDone: state.isInitialImportDone
        )
    }

    /// Phase A: walk the summary endpoint. A handful of requests covers an
    /// entire history, so the list and the global map become usable long before
    /// streams are done.
    @discardableResult
    func syncSummaries() async throws -> Int {
        let state = try state()
        let after = state.lastSummaryEpoch
        var page = 1
        var imported = 0
        var newestEpoch = after

        do {
            while true {
                await setPhase(.summaries(page: page))
                let batch = try await source.activities(
                    after: after, page: page, perPage: Self.pageSize
                )
                if batch.isEmpty { break }

                for dto in batch {
                    let activity = try mapper.upsert(summary: dto)
                    if activity.streams?.latlng == nil,
                       !state.pendingStreamIDs.contains(dto.id) {
                        state.pendingStreamIDs.append(dto.id)
                    }
                    newestEpoch = max(newestEpoch, Int(dto.start_date.timeIntervalSince1970))
                    imported += 1
                }
                try context.save()
                page += 1
            }

            state.lastSummaryEpoch = newestEpoch
            state.isInitialImportDone = true
            state.lastRunAt = Date()
            state.lastErrorMessage = nil
            try context.save()

            let snapshot = await source.rateLimitSnapshot()
            await finish(quota: snapshot, at: state.lastRunAt)
            return imported
        } catch {
            state.lastErrorMessage = error.localizedDescription
            // Swallowed on purpose: a save failure while recording an earlier
            // error must not mask the error we are already reporting.
            try? context.save()
            await setPhase(.failed(error.localizedDescription))
            throw error
        }
    }

    private func setPhase(_ phase: SyncPhase) async {
        await MainActor.run { progress.phase = phase }
    }

    private func finish(quota: RateLimitSnapshot?, at date: Date?) async {
        await MainActor.run {
            progress.phase = .idle
            progress.quota = quota
            progress.lastRunAt = date
        }
    }
}
