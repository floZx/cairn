import Testing
import Foundation
@testable import Cairn

@Suite("TokenStore")
struct TokenStoreTests {
    @Test("un jeton valable plus de 5 minutes n'est pas expiré")
    func freshTokenIsValid() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600)
        )
        #expect(!tokens.isExpired)
    }

    @Test("un jeton qui expire dans moins de 5 minutes est traité comme expiré")
    func nearlyExpiredTokenCountsAsExpired() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(60)
        )
        #expect(tokens.isExpired)
    }

    @Test("un jeton dépassé est expiré")
    func pastTokenIsExpired() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(-1)
        )
        #expect(tokens.isExpired)
    }

    @Test("le store en mémoire respecte le contrat")
    func inMemoryStoreRoundTrips() throws {
        let store = InMemorySecretStore()
        #expect(store.credentials() == nil)
        #expect(store.tokens() == nil)

        let credentials = StravaCredentials(clientID: "123", clientSecret: "secret")
        try store.save(credentials)
        #expect(store.credentials() == credentials)

        let tokens = StravaTokens(
            accessToken: "at", refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try store.save(tokens)
        #expect(store.tokens() == tokens)

        try store.clearTokens()
        #expect(store.tokens() == nil)
        #expect(store.credentials() == credentials)

        try store.clearAll()
        #expect(store.credentials() == nil)
    }

    @Test("les secrets de l'ancien nom sont repris puis relus sans lui")
    func adoptsSecretsFromTheFormerService() throws {
        let legacyService = "com.florianmaisonnial.Cairn.tests.ancien"
        let service = "com.florianmaisonnial.Cairn.tests.nouveau"
        let legacy = KeychainStore(service: legacyService, legacyService: nil)
        let store = KeychainStore(service: service, legacyService: legacyService)
        try legacy.clearAll()
        try store.clearAll()

        let credentials = StravaCredentials(clientID: "42", clientSecret: "shh")
        let tokens = StravaTokens(
            accessToken: "at", refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try legacy.save(credentials)
        try legacy.save(tokens)

        #expect(store.credentials() == credentials)
        #expect(store.tokens() == tokens)

        // The point of the fallback is that it runs once: after the first read
        // the secrets live under the new service, so deleting the old one — or
        // shipping a build without the fallback — changes nothing.
        try legacy.clearAll()
        let withoutFallback = KeychainStore(service: service, legacyService: nil)
        #expect(withoutFallback.credentials() == credentials)
        #expect(withoutFallback.tokens() == tokens)

        try store.clearAll()
    }

    @Test("le Keychain respecte le même contrat")
    func keychainStoreRoundTrips() throws {
        // Dedicated service name so the app's real credentials are never touched
        // — including through the legacy fallback, which would otherwise read
        // the user's actual StravaLocal item and copy it here.
        let store = KeychainStore(
            service: "com.florianmaisonnial.Cairn.tests", legacyService: nil
        )
        try store.clearAll()

        let credentials = StravaCredentials(clientID: "42", clientSecret: "shh")
        try store.save(credentials)
        #expect(store.credentials() == credentials)

        // Rewrite must update in place, not fail on a duplicate item.
        let updated = StravaCredentials(clientID: "43", clientSecret: "shh2")
        try store.save(updated)
        #expect(store.credentials() == updated)

        let tokens = StravaTokens(
            accessToken: "at", refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try store.save(tokens)
        #expect(store.tokens()?.accessToken == "at")
        #expect(store.tokens()?.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))

        // Clearing tokens must not take the credentials with them.
        try store.clearTokens()
        #expect(store.tokens() == nil)
        #expect(store.credentials() == updated)

        try store.clearAll()
        #expect(store.credentials() == nil)
        #expect(store.tokens() == nil)
    }
}
