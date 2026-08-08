// Tests/CatalogUpdaterTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("CatalogUpdater")
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
}
