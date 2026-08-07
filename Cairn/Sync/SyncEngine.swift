import Foundation
import SwiftData

/// Abstracts the network away from the engine so a sync can be tested end to
/// end without HTTP.
///
/// Named for Strava specifically, not just `ActivitySource`, because that name
/// now belongs to the domain enum recording where an `Activity` came from —
/// this protocol is an implementation detail of syncing with one such source.
protocol StravaSyncSource: Sendable {
    func activities(after: Int, page: Int, perPage: Int) async throws -> [SummaryActivityDTO]
    func streams(id: Int64) async throws -> StreamSetDTO
    func activityDetail(id: Int64) async throws -> DetailActivityDTO
    func photos(id: Int64) async throws -> [PhotoDTO]
    func imageData(from url: URL) async throws -> Data
    func athlete() async throws -> AthleteDTO
    func gear(id: String) async throws -> GearDTO
    func rateLimitSnapshot() async -> RateLimitSnapshot?
    func delayBeforeNextRequest() async -> TimeInterval
}

/// `StravaClient` already has every one of these signatures, so the conformance
/// needs no bridging methods — adding one here would just recurse.
extension StravaClient: StravaSyncSource {}

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
    private let source: StravaSyncSource
    private let container: ModelContainer
    private let progress: SyncProgress
    private let context: ModelContext
    private let mapper: ImportMapper

    private static let pageSize = 200

    init(source: StravaSyncSource, container: ModelContainer, progress: SyncProgress) {
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
                    do {
                        let activity = try mapper.upsert(summary: dto)
                        // "Never fetched", not "has no track". The two differ for
                        // every indoor ride, pool swim and gym session: Strava
                        // returns their streams with no `latlng` at all, so the
                        // old condition stayed true after a successful fetch and
                        // put them straight back in the queue. Measured: 102 of
                        // the 841 activities were queued while already holding
                        // their streams, every one of them trackless.
                        if activity.streams == nil,
                           !state.pendingStreamIDs.contains(dto.id) {
                            state.pendingStreamIDs.append(dto.id)
                        }
                        imported += 1
                    } catch ImportSkip.discarded {
                        // Not queued for phase B either: a stream request for an
                        // activity the user deleted would just burn quota.
                        //
                        // The `continue` also skips advancing `newestEpoch`
                        // below, and that is deliberate, not an oversight: the
                        // cursor must stay short of a discarded activity's date,
                        // because `restore` only pulls it back, never forward.
                        // If this activity were the newest in the batch and the
                        // cursor advanced past it anyway, reinstating it later
                        // would leave no incremental sync able to reach it again.
                        continue
                    }
                    newestEpoch = max(newestEpoch, Int(dto.start_date.timeIntervalSince1970))
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

    /// Phase B: one request per activity, popped off a persisted queue.
    ///
    /// The queue entry is only removed once the streams are saved, so an
    /// interruption at any point leaves the work still recorded as pending.
    @discardableResult
    func syncStreams(limit: Int? = nil) async throws -> Int {
        // Named `initial` rather than `state`: a local called `state` would
        // shadow the `state()` method the loop below re-reads on each iteration.
        let initial = try state()
        let total = initial.pendingStreamIDs.count
        guard total > 0 else {
            await finish(quota: await source.rateLimitSnapshot(), at: initial.lastRunAt)
            return 0
        }

        do {
            return try await drainStreamQueue(limit: limit, total: total)
        } catch {
            let state = try? state()
            state?.lastErrorMessage = error.localizedDescription
            try? context.save()
            await setPhase(.failed(error.localizedDescription))
            throw error
        }
    }

    /// Phase B's walk. One request per activity, popped off a persisted queue.
    ///
    /// The queue entry is only removed once the streams are saved, so an
    /// interruption at any point leaves the work still recorded as pending.
    private func drainStreamQueue(limit: Int?, total: Int) async throws -> Int {
        var fetched = 0
        // Counts every request actually issued, including ones that 404. A 404
        // still spends a request against the quota, so `limit` has to bound
        // attempts rather than successes — otherwise a run of deleted
        // activities blows straight through the caller's budget.
        var attempts = 0
        let budget = limit ?? total

        while attempts < budget {
            if Task.isCancelled { break }
            let current = try state()
            guard let stravaID = current.pendingStreamIDs.first else { break }

            // The initial import queues thousands of identifiers that phase B
            // only drains over several days at 200 requests per quarter hour —
            // deleting activities during that window is the normal case, not
            // an edge case. Checked here, not in `discard`: `discard` runs from
            // the timeline's own context, and having it reach into `SyncState`
            // while this actor holds its own context is a race worth avoiding.
            if try mapper.isDiscarded(stravaID: stravaID) {
                try dequeue(stravaID)
                continue
            }

            // Already held: drop it without spending a request. This is what
            // clears a backlog queued under the old condition — otherwise those
            // 102 trackless activities each cost a request to re-download
            // streams already on disk.
            if try mapper.activity(stravaID: stravaID)?.streams != nil {
                try dequeue(stravaID)
                continue
            }

            // Ask before spending: the limiter would otherwise sleep inside the
            // HTTP client, leaving the UI on a frozen counter for up to fifteen
            // minutes and looking hung when it is merely waiting its turn.
            let wait = await source.delayBeforeNextRequest()
            if wait > 0 {
                await setPhase(.waitingForQuota(until: Date().addingTimeInterval(wait)))
                do {
                    try await Task.sleep(for: .seconds(wait))
                } catch {
                    break
                }
            }

            await setPhase(.streams(done: fetched, total: min(budget, total)))

            do {
                let streams = try await source.streams(id: stravaID)
                attempts += 1
                if let activity = try mapper.activity(stravaID: stravaID) {
                    mapper.apply(streams: streams, to: activity)
                    fetched += 1
                } else {
                    // The fetch succeeded but the row is gone, so nothing was
                    // saved. Dequeue anyway — retrying cannot help — but leave
                    // a trace rather than silently discarding a real request.
                    current.lastErrorMessage =
                        "Activité \(stravaID) absente de la base, streams ignorés"
                }
                try dequeue(stravaID)
            } catch let StravaError.http(status, message) where status == 404 {
                // The activity is gone from Strava: dropping it from the queue
                // is the only way to make progress.
                attempts += 1
                current.lastErrorMessage =
                    "Activité \(stravaID) introuvable : \(message)"
                try dequeue(stravaID)
            } catch let StravaError.http(status, _) where status == 429 {
                let resumeAt = Date().addingTimeInterval(
                    RateLimiter.secondsUntilNextShortWindow(from: Date())
                )
                await setPhase(.waitingForQuota(until: resumeAt))
                current.lastErrorMessage = "Quota Strava atteint"
                try context.save()
                return fetched
            }
        }

        let finalState = try state()
        finalState.lastRunAt = Date()
        try context.save()
        await finish(quota: await source.rateLimitSnapshot(), at: finalState.lastRunAt)
        return fetched
    }

    /// Puts an identifier back in the queue, to reproduce a backlog left by an
    /// earlier version. Exists for the test that proves such a backlog costs no
    /// request; production never needs it.
    func enqueueForTesting(stravaID: Int64) throws {
        let state = try state()
        guard !state.pendingStreamIDs.contains(stravaID) else { return }
        state.pendingStreamIDs.append(stravaID)
        try context.save()
    }

    private func dequeue(_ stravaID: Int64) throws {
        let state = try state()
        state.pendingStreamIDs.removeAll { $0 == stravaID }
        try context.save()
    }

    func syncAll() async throws {
        try await syncAthlete()
        try await syncSummaries()
        try await syncGear()
        try await syncStreams()
    }

    /// Fetches the gear referenced by imported activities and links it up. Only
    /// a handful of requests — a rider owns a few bikes, not a few thousand.
    func syncGear() async throws {
        let activities = try context.fetch(
            FetchDescriptor<Activity>(predicate: #Predicate { $0.gearID != nil })
        )
        let unlinked = activities.filter { $0.gear == nil }
        guard !unlinked.isEmpty else { return }

        var failures = 0
        for gearID in Set(unlinked.compactMap(\.gearID)) {
            let dto: GearDTO
            do {
                dto = try await source.gear(id: gearID)
            } catch {
                // Deleted or inaccessible gear must not stall the whole sync,
                // but a systematic failure has to leave a trace.
                failures += 1
                continue
            }
            let gear = try mapper.upsert(gear: dto)
            for activity in unlinked where activity.gearID == gearID {
                activity.gear = gear
            }
        }

        if failures > 0 {
            let state = try state()
            state.lastErrorMessage =
                "Matériel non récupéré pour \(failures) référence(s)"
        }
        try context.save()
    }

    /// Re-imports every summary from scratch, so edits made on Strava after the
    /// fact — a renamed activity, a corrected sport, an edited note — land
    /// locally.
    ///
    /// Streams are deliberately left alone: a recorded track does not change,
    /// and re-fetching them would cost one request per activity. The detail
    /// cache *is* cleared, because description, laps and device come from the
    /// detail endpoint and are otherwise fetched once and kept forever.
    func resyncEverything() async throws {
        let state = try state()
        state.lastSummaryEpoch = 0
        // Only Strava's own activities have a detail worth re-fetching; clearing
        // it on a local one would just make `fetchDetailIfNeeded` retry forever.
        for activity in try context.fetch(FetchDescriptor<Activity>())
        where activity.source.isSynced {
            activity.detailFetchedAt = nil
            activity.photosFetchedAt = nil
        }
        try context.save()

        try await syncAthlete()
        try await syncSummaries()
        try await syncGear()
    }

    func syncAthlete() async throws {
        let dto = try await source.athlete()
        try mapper.upsert(athlete: dto)
        try context.save()
    }

    /// Fetches the detail endpoint lazily, on first open of an activity. Halves
    /// the cost of the initial sync compared to fetching it up front.
    func fetchDetailIfNeeded(stravaID: Int64) async throws {
        guard let activity = try mapper.activity(stravaID: stravaID),
              activity.source.isSynced
        else { return }

        // Two markers, checked separately. Bundling them behind the detail's
        // guard is what made photos unreachable for every activity synced
        // before they existed: their detail date was already set, so opening
        // one returned here and asked Strava nothing.
        var detail: DetailActivityDTO?
        if activity.detailFetchedAt == nil {
            let fetched = try await source.activityDetail(id: stravaID)
            try mapper.apply(detail: fetched, to: activity)
            try context.save()
            detail = fetched
        }
        try await fetchPhotosIfNeeded(activity, detail: detail)
    }

    /// Fetches an activity's streams now, ahead of the queue.
    ///
    /// Phase B drains thousands of identifiers over days at 200 requests per
    /// quarter hour, so an activity recorded this morning sits far down the line
    /// — and its detail pane shows a track with no elevation and no heart rate,
    /// looking exactly like a ride that never recorded either. Opening one is a
    /// clear statement of which activity matters right now, so it jumps the
    /// queue.
    ///
    /// Dequeued on success so phase B does not spend a second request on it.
    func fetchStreamsIfNeeded(stravaID: Int64) async throws {
        guard let activity = try mapper.activity(stravaID: stravaID),
              activity.source.isSynced,
              activity.streams == nil
        else { return }

        let dto = try await source.streams(id: stravaID)
        mapper.apply(streams: dto, to: activity)
        try dequeue(stravaID)
        try context.save()
    }

    /// Looks for an activity's photos once, whether or not its detail was
    /// fetched long ago.
    ///
    /// This is the whole reason `photosFetchedAt` exists rather than reusing
    /// `detailFetchedAt`: every activity synced before photos were supported
    /// already carries a detail date, so hanging the photo fetch off that marker
    /// would mean the entire existing library never looks for a photo at all.
    ///
    /// `detail` is whatever the caller already has in hand, so opening an
    /// activity for the first time costs no extra request.
    func fetchPhotosIfNeeded(
        _ activity: Activity, detail: DetailActivityDTO? = nil
    ) async throws {
        guard activity.source.isSynced, activity.photosFetchedAt == nil else { return }
        // A known zero costs nothing: the summary already said there is nothing
        // to look for. Nil is *unknown*, not zero — everything synced before
        // `total_photo_count` was read — and unknown still deserves a look.
        guard activity.photoCount != 0 else {
            activity.photosFetchedAt = Date()
            try context.save()
            return
        }

        var listed = try await source.photos(id: activity.stravaID)
        // Nothing came back from the undocumented endpoint, so fall back to the
        // one documented photo — but only pay for it when it is worth paying
        // for. A detail already in hand is free, whatever the count says. Going
        // back to Strava for one is not, so that branch waits until the summary
        // has actually claimed there are photos to find.
        if listed.isEmpty {
            if let primary = detail?.photos?.primary {
                listed = [primary]
            } else if (activity.photoCount ?? 0) > 0,
                      let refetched = try? await source.activityDetail(
                          id: activity.stravaID
                      ),
                      let primary = refetched.photos?.primary {
                listed = [primary]
            }
        }

        let pending = mapper.upsert(photos: listed, on: activity)
        // Set before the downloads, not after: the rows are what matters, and a
        // CDN that refuses one image must not make the next sync ask Strava for
        // the whole list again.
        activity.photosFetchedAt = Date()
        try context.save()

        for photo in pending {
            guard let address = photo.sourceURL, let url = URL(string: address),
                  let data = try? await source.imageData(from: url)
            else { continue }
            photo.data = data
        }
        try context.save()
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
