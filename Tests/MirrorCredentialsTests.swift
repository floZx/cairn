import Testing
import Foundation
@testable import Cairn

@Suite("Identifiants du miroir")
struct MirrorCredentialsTests {
    /// La marge de cinq minutes qui protège `StravaTokens` protège aussi une
    /// session du miroir : un push long ne doit pas démarrer sur un jeton qui
    /// meurt en vol.
    @Test func uneSessionQuiExpireDansLaMinuteEstDejaExpiree() {
        let session = MirrorSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(60), userID: "u"
        )
        #expect(session.isExpired)
    }

    @Test func uneSessionQuiExpireDansUneHeureNeLEstPas() {
        let session = MirrorSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600), userID: "u"
        )
        #expect(!session.isExpired)
    }

    /// Effacer le miroir ne touche pas à Strava. Ce sont deux relations
    /// indépendantes, et se déconnecter de l'une ne dit rien de l'autre.
    @Test func effacerLeMiroirLaisseStravaEnPlace() throws {
        let store = InMemorySecretStore(
            credentials: StravaCredentials(clientID: "c", clientSecret: "s")
        )
        try store.save(
            MirrorCredentials(
                projectURL: URL(string: "https://x.supabase.co")!, anonKey: "k"
            )
        )
        try store.clearMirror()

        #expect(store.mirrorCredentials() == nil)
        #expect(store.credentials() != nil)
    }

    @Test func leStoreEnMemoireFaitLesAllersRetours() throws {
        let store = InMemorySecretStore()
        #expect(store.mirrorCredentials() == nil)
        #expect(store.mirrorSession() == nil)

        let credentials = MirrorCredentials(
            projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
        )
        try store.save(credentials)
        #expect(store.mirrorCredentials() == credentials)

        let session = MirrorSession(
            accessToken: "jeton", refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000), userID: "u1"
        )
        try store.save(session)
        #expect(store.mirrorSession() == session)

        try store.clearMirror()
        #expect(store.mirrorCredentials() == nil)
        #expect(store.mirrorSession() == nil)
    }

    @Test func leKeychainRespecteLeMemeContrat() throws {
        // Dedicated service name so the app's real credentials are never
        // touched. No legacy service: Supabase has no former name to fall
        // back to.
        let store = KeychainStore(
            service: "com.florianmaisonnial.Cairn.tests.mirror", legacyService: nil
        )
        try store.clearAll()
        try store.clearMirror()

        let credentials = MirrorCredentials(
            projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
        )
        try store.save(credentials)
        #expect(store.mirrorCredentials() == credentials)

        let session = MirrorSession(
            accessToken: "jeton", refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000), userID: "u1"
        )
        try store.save(session)
        #expect(store.mirrorSession()?.accessToken == "jeton")
        #expect(store.mirrorSession()?.userID == "u1")

        try store.clearMirror()
        #expect(store.mirrorCredentials() == nil)
        #expect(store.mirrorSession() == nil)
    }
}
