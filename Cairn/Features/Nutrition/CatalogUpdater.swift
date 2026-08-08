// Cairn/Features/Nutrition/CatalogUpdater.swift
import Foundation

/// The state machine behind "Mettre à jour le catalogue": download the CSV
/// export (resumable), build off.db off the main actor, report progress,
/// survive cancellation. One instance per settings screen; the pipeline
/// closures are injectable so the machine is testable without network.
@MainActor @Observable
final class CatalogUpdater {
    enum Phase: Equatable {
        case idle
        case downloading(megabytes: Double, totalMegabytes: Double?)
        case building(kept: Int)
        case done(count: Int)
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle

    var isRunning: Bool {
        switch phase {
        case .downloading, .building: return true
        case .idle, .done, .failed: return false
        }
    }

    /// Kept outside Application Support/Cairn's store files: a partial
    /// download surviving for resume is cache, not user data.
    static var cacheURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Cairn/cache/food.csv.gz")
    }

    private let download: @Sendable (
        URL, URL, @Sendable @escaping (Int64, Int64?) -> Void
    ) async throws -> Void
    private let buildCatalog: @Sendable (
        String, String, String, @Sendable @escaping (Int, Int) -> Void
    ) throws -> Int
    private var task: Task<Void, Never>?

    init(
        download: @escaping @Sendable (
            URL, URL, @Sendable @escaping (Int64, Int64?) -> Void
        ) async throws -> Void = { url, destination, progress in
            try await FileDownloader.download(
                from: url, to: destination, onProgress: progress
            )
        },
        build: @escaping @Sendable (
            String, String, String, @Sendable @escaping (Int, Int) -> Void
        ) throws -> Int = { gzPath, dbPath, date, progress in
            try CatalogBuilder.build(
                gzPath: gzPath, offDBPath: dbPath, importedAt: date,
                onProgress: progress
            )
        }
    ) {
        self.download = download
        self.buildCatalog = build
    }

    func start() {
        guard !isRunning else { return }
        phase = .downloading(megabytes: 0, totalMegabytes: nil)
        let download = download
        let buildCatalog = buildCatalog
        task = Task { [weak self] in
            // Unwrapped once, into a `let`: the nested progress closures
            // below are `@Sendable` (FileDownloader/CatalogBuilder invoke
            // `onProgress` off the main actor), and Swift 6 refuses to
            // recapture a *weak var* — which is what a bare `[weak self]`
            // produces inside this task body — across that boundary
            // ("reference to captured var 'self' in concurrently-executing
            // code"). A `let` sidesteps it; the nested closures re-weaken it
            // themselves so a slow download/build still can't outlive an
            // abandoned updater.
            guard let self else { return }
            do {
                let cache = Self.cacheURL
                try await download(CatalogBuilder.catalogURL, cache) {
                    bytes, total in
                    Task { @MainActor [weak self] in
                        guard self?.isRunning == true else { return }
                        self?.phase = .downloading(
                            megabytes: Double(bytes) / 1_048_576,
                            totalMegabytes: total.map { Double($0) / 1_048_576 }
                        )
                    }
                }
                await MainActor.run {
                    self.phase = .building(kept: 0)
                }
                let importedAt = ISO8601DateFormatter()
                    .string(from: Date()).prefix(10)
                // FoodCatalog.defaultURL is @MainActor-isolated; read it here
                // (this task body inherited MainActor isolation from
                // `start()`) and hand the plain path down — `group.addTask`
                // below spins up a non-isolated child task that cannot
                // access a MainActor-isolated static property directly.
                let dbPath = FoodCatalog.defaultURL.path
                // A task group rather than Task.detached: detached tasks do
                // NOT inherit cancellation, and « Annuler » must reach the
                // builder's Task.checkCancellation().
                let count = try await withThrowingTaskGroup(of: Int.self) { group in
                    group.addTask(priority: .utility) {
                        try buildCatalog(
                            cache.path, dbPath, String(importedAt)
                        ) { _, kept in
                            Task { @MainActor [weak self] in
                                guard self?.isRunning == true else { return }
                                self?.phase = .building(kept: kept)
                            }
                        }
                    }
                    guard let result = try await group.next() else {
                        throw CancellationError()
                    }
                    return result
                }
                // The gz cache only matters for resuming; a finished build
                // has no use for a gigabyte on disk.
                try? FileManager.default.removeItem(at: cache)
                await MainActor.run {
                    self.phase = .done(count: count)
                }
            } catch is CancellationError {
                // The .part stays on disk: cancelling is pausing.
                await MainActor.run {
                    self.phase = .idle
                }
            } catch {
                // Not `error.localizedDescription`: neither DownloadError nor
                // BuildError conforms to LocalizedError, so that would print
                // Foundation's generic "The operation couldn't be completed"
                // instead of the message they carry. String interpolation
                // uses their CustomStringConvertible.description.
                await MainActor.run {
                    self.phase = .failed(
                        message: "La mise à jour a échoué : \(error)"
                    )
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func waitUntilFinished() async {
        await task?.value
    }
}
