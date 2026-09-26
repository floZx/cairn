import Foundation
import Security

struct StravaCredentials: Sendable, Equatable, Codable {
    let clientID: String
    let clientSecret: String
}

struct StravaTokens: Sendable, Equatable, Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// Treated as expired five minutes early so a long request can't start on a
    /// token that dies mid-flight.
    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 300
    }
}

protocol SecretStore: Sendable {
    func credentials() -> StravaCredentials?
    func save(_ credentials: StravaCredentials) throws
    func tokens() -> StravaTokens?
    func save(_ tokens: StravaTokens) throws
    func clearTokens() throws
    func clearAll() throws

    func mirrorCredentials() -> MirrorCredentials?
    func save(_ credentials: MirrorCredentials) throws
    func mirrorSession() -> MirrorSession?
    func save(_ session: MirrorSession) throws
    /// Drops the session only, in mirror of `clearTokens()`: a rejected
    /// refresh means the session is dead, not that the project itself was
    /// misconfigured, so the project URL and anon key must survive it.
    func clearMirrorSession() throws
    func clearMirror() throws

    func garminTokens() -> GarminTokens?
    func save(_ tokens: GarminTokens) throws
    func clearGarminTokens() throws

    /// La clé du journal chiffré, une fois la phrase saisie sur ce Mac.
    func journalKey() -> JournalKey?
    func save(_ key: JournalKey) throws
    func clearJournalKey() throws
}

enum SecretStoreError: Error {
    case keychain(OSStatus)
}

/// Generic-password Keychain items, one per record, keyed by account name.
/// Values are JSON so adding a field later doesn't need a migration.
final class KeychainStore: SecretStore, Sendable {
    private let service: String
    /// The service the app used under its former name. Items are copied across on
    /// first read rather than at launch, so an install that never had a
    /// StravaLocal keychain pays nothing and a rename doesn't ask the user to sign
    /// in to Strava all over again.
    private let legacyService: String?
    private static let credentialsAccount = "credentials"
    private static let tokensAccount = "tokens"
    private static let mirrorCredentialsAccount = "mirror-credentials"
    private static let mirrorSessionAccount = "mirror-session"
    private static let garminTokensAccount = "garmin-tokens"
    private static let journalKeyAccount = "journal-key"

    init(
        service: String = "com.florianmaisonnial.Cairn",
        legacyService: String? = "com.florianmaisonnial.StravaLocal"
    ) {
        self.service = service
        self.legacyService = legacyService
    }

    func credentials() -> StravaCredentials? {
        adopting(StravaCredentials.self, account: Self.credentialsAccount)
    }

    func save(_ credentials: StravaCredentials) throws {
        try write(credentials, account: Self.credentialsAccount)
    }

    func tokens() -> StravaTokens? {
        adopting(StravaTokens.self, account: Self.tokensAccount)
    }

    /// Reads under the current service, falling back to the former one and
    /// copying what it finds so the next read no longer needs the fallback.
    private func adopting<T: Codable>(_ type: T.Type, account: String) -> T? {
        if let value = read(type, account: account) { return value }
        guard let legacyService,
              let value = read(type, account: account, service: legacyService)
        else { return nil }
        // A failed copy is not worth surfacing: the value was still read, and the
        // fallback will simply run again next time.
        try? write(value, account: account)
        return value
    }

    func save(_ tokens: StravaTokens) throws {
        try write(tokens, account: Self.tokensAccount)
    }

    /// Deletes the former service's copy too. `adopting` reads it whenever
    /// the current one is missing, so deleting only the current one signed
    /// nobody out: the next read copied the old tokens straight back.
    func clearTokens() throws {
        try delete(account: Self.tokensAccount)
        try deleteLegacy(account: Self.tokensAccount)
    }

    func clearAll() throws {
        try clearTokens()
        try delete(account: Self.credentialsAccount)
        try deleteLegacy(account: Self.credentialsAccount)
    }

    /// No `legacyService` fallback here: Supabase has no former name to
    /// adopt secrets from, so a plain read avoids a wasted Keychain lookup
    /// on every call.
    func mirrorCredentials() -> MirrorCredentials? {
        read(MirrorCredentials.self, account: Self.mirrorCredentialsAccount)
    }

    func save(_ credentials: MirrorCredentials) throws {
        try write(credentials, account: Self.mirrorCredentialsAccount)
    }

    func mirrorSession() -> MirrorSession? {
        read(MirrorSession.self, account: Self.mirrorSessionAccount)
    }

    func save(_ session: MirrorSession) throws {
        try write(session, account: Self.mirrorSessionAccount)
    }

    func clearMirrorSession() throws {
        try delete(account: Self.mirrorSessionAccount)
    }

    func clearMirror() throws {
        try delete(account: Self.mirrorSessionAccount)
        try delete(account: Self.mirrorCredentialsAccount)
    }

    func garminTokens() -> GarminTokens? {
        read(GarminTokens.self, account: Self.garminTokensAccount)
    }

    func save(_ tokens: GarminTokens) throws {
        try write(tokens, account: Self.garminTokensAccount)
    }

    func clearGarminTokens() throws {
        try delete(account: Self.garminTokensAccount)
    }

    func journalKey() -> JournalKey? {
        read(JournalKey.self, account: Self.journalKeyAccount)
    }

    func save(_ key: JournalKey) throws {
        try write(key, account: Self.journalKeyAccount)
    }

    func clearJournalKey() throws {
        try delete(account: Self.journalKeyAccount)
    }

    private func baseQuery(account: String, service: String? = nil) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? self.service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read<T: Decodable>(
        _ type: T.Type, account: String, service: String? = nil
    ) -> T? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.keychain(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.keychain(addStatus)
        }
    }

    private func deleteLegacy(account: String) throws {
        guard let legacyService else { return }
        try delete(account: account, service: legacyService)
    }

    private func delete(account: String, service: String? = nil) throws {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }
}

/// Non-persistent implementation, used to test everything that depends on
/// secrets without touching the user's Keychain.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCredentials: StravaCredentials?
    private var storedTokens: StravaTokens?
    private var storedMirrorCredentials: MirrorCredentials?
    private var storedMirrorSession: MirrorSession?
    private var storedGarminTokens: GarminTokens?
    private var storedJournalKey: JournalKey?

    init(credentials: StravaCredentials? = nil, tokens: StravaTokens? = nil) {
        storedCredentials = credentials
        storedTokens = tokens
    }

    func credentials() -> StravaCredentials? {
        lock.withLock { storedCredentials }
    }

    func save(_ credentials: StravaCredentials) throws {
        lock.withLock { storedCredentials = credentials }
    }

    func tokens() -> StravaTokens? {
        lock.withLock { storedTokens }
    }

    func save(_ tokens: StravaTokens) throws {
        lock.withLock { storedTokens = tokens }
    }

    func clearTokens() throws {
        lock.withLock { storedTokens = nil }
    }

    func clearAll() throws {
        lock.withLock {
            storedTokens = nil
            storedCredentials = nil
        }
    }

    func mirrorCredentials() -> MirrorCredentials? {
        lock.withLock { storedMirrorCredentials }
    }

    func save(_ credentials: MirrorCredentials) throws {
        lock.withLock { storedMirrorCredentials = credentials }
    }

    func mirrorSession() -> MirrorSession? {
        lock.withLock { storedMirrorSession }
    }

    func save(_ session: MirrorSession) throws {
        lock.withLock { storedMirrorSession = session }
    }

    func clearMirrorSession() throws {
        lock.withLock { storedMirrorSession = nil }
    }

    func clearMirror() throws {
        lock.withLock {
            storedMirrorSession = nil
            storedMirrorCredentials = nil
        }
    }

    func garminTokens() -> GarminTokens? {
        lock.withLock { storedGarminTokens }
    }

    func save(_ tokens: GarminTokens) throws {
        lock.withLock { storedGarminTokens = tokens }
    }

    func clearGarminTokens() throws {
        lock.withLock { storedGarminTokens = nil }
    }

    func journalKey() -> JournalKey? {
        lock.withLock { storedJournalKey }
    }

    func save(_ key: JournalKey) throws {
        lock.withLock { storedJournalKey = key }
    }

    func clearJournalKey() throws {
        lock.withLock { storedJournalKey = nil }
    }
}
