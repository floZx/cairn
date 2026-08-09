// Tests/CatalogUpdaterTests.swift
import Testing
import Foundation
@testable import Cairn

// Serialized: `CatalogUpdater.inFlight` (finding 3's single-flight guard) is
// a process-wide `static var`. Swift Testing otherwise interleaves this
// suite's async tests on the MainActor, and two tests racing to `start()`
// while another is still mid-flight would trip each other's guard and
// intermittently fail for reasons unrelated to what each test is checking.
@Suite("CatalogUpdater", .serialized)
@MainActor
struct CatalogUpdaterTests {
    @Test("le pipeline complet passe par téléchargement, build et done")
    func fullPipelineReachesDone() async {
        let updater = CatalogUpdater(
            download: { _, _, progress in progress(1_000_000, 2_000_000) },
            build: { _, _, _, progress in
                progress(10, 4)
                return 4
            }
        )
        updater.start()
        await updater.waitUntilFinished()
        #expect(updater.phase == .done(count: 4))
        #expect(!updater.isRunning)
    }

    @Test("un échec de téléchargement finit en failed avec le message")
    func downloadFailureSurfaces() async {
        let updater = CatalogUpdater(
            download: { _, _, _ in
                throw FileDownloader.DownloadError(message: "coupure réseau")
            },
            build: { _, _, _, _ in 0 }
        )
        updater.start()
        await updater.waitUntilFinished()
        guard case let .failed(message) = updater.phase else {
            Issue.record("attendu failed, obtenu \(updater.phase)")
            return
        }
        #expect(message.contains("coupure réseau"))
    }

    @Test("l'annulation retombe sur idle, pas sur failed")
    func cancellationReturnsToIdle() async {
        let updater = CatalogUpdater(
            download: { _, _, _ in
                // Un téléchargement qui ne finit jamais de lui-même.
                try await Task.sleep(for: .seconds(60))
            },
            build: { _, _, _, _ in 0 }
        )
        updater.start()
        updater.cancel()
        await updater.waitUntilFinished()
        #expect(updater.phase == .idle)
        #expect(!updater.isRunning)
    }

    @Test(
        "une annulation qui ressort en URLError(.cancelled) retombe aussi sur idle"
    )
    func urlErrorCancelledAfterCancelReturnsToIdle() async {
        // Mirrors StreamingFetch.run's onCancel path: cancelling while only
        // waiting for headers makes URLSession fail the task with
        // URLError(.cancelled), a plain error rather than CancellationError.
        // A caller catching only `is CancellationError` would miss it and
        // paint a red « échoué » — this exercises CatalogUpdater's
        // Task.isCancelled fallback in its generic `catch`.
        let updater = CatalogUpdater(
            download: { _, _, _ in
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    throw URLError(.cancelled)
                }
            },
            build: { _, _, _, _ in 0 }
        )
        updater.start()
        updater.cancel()
        await updater.waitUntilFinished()
        #expect(updater.phase == .idle)
        #expect(!updater.isRunning)
    }

    @Test("un second start() pendant un run en cours reste sans effet")
    func secondStartWhileRunningIsNoOp() async {
        let first = CatalogUpdater(
            download: { _, _, _ in
                // Un téléchargement qui ne finit jamais de lui-même.
                try await Task.sleep(for: .seconds(60))
            },
            build: { _, _, _, _ in 0 }
        )
        let second = CatalogUpdater(
            download: { _, _, _ in },
            build: { _, _, _, _ in 0 }
        )
        first.start()
        // The single-flight guard is process-wide (static), so the second
        // instance's start() must be rejected while the first is still
        // running, even though the two are unrelated CatalogUpdater values.
        second.start()
        #expect(second.phase == .idle)
        #expect(!second.isRunning)

        first.cancel()
        await first.waitUntilFinished()
        #expect(first.phase == .idle)

        // Once the first run has released the guard, a fresh start()
        // succeeds — proving `inFlight` was actually cleared, not just
        // never set.
        second.start()
        await second.waitUntilFinished()
        #expect(second.phase == .done(count: 0))
    }

    @Test("un gz complet en cache saute le téléchargement")
    func existingCacheSkipsDownload() async throws {
        // A throwaway file under the temp directory, not the real
        // `~/Library/Application Support/Cairn/cache` — this test writes to
        // and deletes its cache file, and must not touch the user's actual
        // catalogue cache.
        let cache = FileManager.default.temporaryDirectory
            .appending(path: "CatalogUpdaterTests-\(UUID()).csv.gz")
        try Data("gz factice".utf8).write(to: cache)
        defer { try? FileManager.default.removeItem(at: cache) }

        let updater = CatalogUpdater(
            cacheURL: cache,
            download: { _, _, _ in
                Issue.record("le téléchargement ne devait pas être appelé")
            },
            build: { _, _, _, _ in 7 }
        )
        updater.start()
        await updater.waitUntilFinished()
        #expect(updater.phase == .done(count: 7))
    }
}
