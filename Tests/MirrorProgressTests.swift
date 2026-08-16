import Testing
import Foundation
@testable import Cairn

@Suite("État du miroir")
@MainActor
struct MirrorProgressTests {
    /// Jamais muet : un miroir jamais configuré et un miroir à jour ne doivent
    /// pas se lire pareil. C'est la leçon déjà tirée sur `SyncProgress`.
    @Test func unMiroirJamaisConfigureLeDit() {
        let progress = MirrorProgress()
        #expect(progress.statusText.contains("Jamais"))
    }

    @Test func unAmorcageEnCoursAnnonceOuIlEnEst() {
        let progress = MirrorProgress()
        progress.phase = .bootstrapping(table: "activity", done: 120, total: 852)
        #expect(progress.statusText.contains("120"))
        #expect(progress.statusText.contains("852"))
    }

    @Test func unEchecEstDit() {
        let progress = MirrorProgress()
        progress.phase = .failed("réseau injoignable")
        #expect(progress.statusText.contains("réseau injoignable"))
    }
}
