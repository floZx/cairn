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

    // `phase`/`task`/`isRunning` are per-instance, but the settings screen
    // recreates a fresh `CatalogUpdater` `@State` every time Réglages is
    // reopened. Closing the window mid-download and reopening it makes a
    // brand-new, idle updater that has never heard of the run still writing
    // to the shared `.part` file — its own `isRunning` guard in `start()` is
    // blind to that. A `static` guard is visible to every instance and
    // closes that gap: at most one download/build can be in flight for the
    // whole process, matching the single `.part`/cache file they all share.
    @MainActor private static var inFlight = false

    var isRunning: Bool {
        switch phase {
        case .downloading, .building: return true
        case .idle, .done, .failed: return false
        }
    }

    /// Kept outside Application Support/Cairn's store files: a partial
    /// download surviving for resume is cache, not user data.
    static var defaultCacheURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Cairn/cache/food.csv.gz")
    }

    /// Alias kept for existing call sites reading the static property.
    static var cacheURL: URL { defaultCacheURL }

    /// Per-instance, defaulting to the real cache path: lets tests point a
    /// `CatalogUpdater` at a throwaway file instead of writing to and
    /// deleting the user's actual `~/Library/Application Support` cache.
    let cacheURL: URL

    private let download: @Sendable (
        URL, URL, @Sendable @escaping (Int64, Int64?) -> Void
    ) async throws -> Void
    private let buildCatalog: @Sendable (
        String, String, String, @Sendable @escaping (Int, Int) -> Void
    ) throws -> Int
    private var task: Task<Void, Never>?

    init(
        cacheURL: URL = CatalogUpdater.defaultCacheURL,
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
        self.cacheURL = cacheURL
        self.download = download
        self.buildCatalog = build
    }

    func start() {
        guard !isRunning else { return }
        // Single-flight across instances, not just within this one — see
        // `inFlight`'s doc comment.
        guard !Self.inFlight else { return }
        Self.inFlight = true
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
            guard let self else {
                // The updater died between start() and this first tick: the
                // process-wide guard must not stay latched forever.
                Self.inFlight = false
                return
            }
            do {
                let cache = self.cacheURL
                // A complete gz survives a failed build (the .part flow only
                // covers interrupted downloads): reuse it instead of paying
                // the gigabyte again. A finished build deletes it either way.
                if !FileManager.default.fileExists(atPath: cache.path) {
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
                }
                await MainActor.run {
                    self.phase = .building(kept: 0)
                }
                // Not ISO8601DateFormatter: it defaults to UTC, which before
                // ~01:00 CET is still yesterday there. The app's day identity
                // is the LOCAL calendar day everywhere else (DateKey), and
                // `imported_at` should agree with it.
                let importedAt = DateKey(Date()).raw
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
                    Self.inFlight = false
                }
            } catch is CancellationError {
                // The .part stays on disk: cancelling is pausing.
                await MainActor.run {
                    self.phase = .idle
                    Self.inFlight = false
                }
            } catch {
                // A cancellation during the header wait (StreamingFetch.run's
                // withTaskCancellationHandler) surfaces as URLError(.cancelled)
                // from URLSession, not CancellationError — the mapping back to
                // Swift's cancellation vocabulary lives in StreamingFetch,
                // which this generic catch cannot see into. Checking
                // Task.isCancelled here catches that case too: cancelling
                // must always look like a pause (→ .idle), never a red
                // « La mise à jour a échoué » failure.
                if Task.isCancelled {
                    await MainActor.run {
                        self.phase = .idle
                        Self.inFlight = false
                    }
                    return
                }
                // A genuine failure (not a cancellation) taints whatever gz
                // sits at `cache`: it may be exactly what made the download
                // or the build blow up, and the skip-download branch above
                // would otherwise hand that same broken file back on every
                // retry, failing identically forever with no way out short
                // of the user manually finding and deleting it. Purge it so
                // the next attempt starts clean.
                try? FileManager.default.removeItem(at: self.cacheURL)
                // Not `error.localizedDescription`: neither DownloadError nor
                // BuildError conforms to LocalizedError, so that would print
                // Foundation's generic "The operation couldn't be completed"
                // instead of the message they carry. String interpolation
                // uses their CustomStringConvertible.description.
                await MainActor.run {
                    self.phase = .failed(
                        message: "La mise à jour a échoué : \(error)"
                    )
                    Self.inFlight = false
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
