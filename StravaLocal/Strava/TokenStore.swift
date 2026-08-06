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
}

enum SecretStoreError: Error {
    case keychain(OSStatus)
}

/// Generic-password Keychain items, one per record, keyed by account name.
/// Values are JSON so adding a field later doesn't need a migration.
final class KeychainStore: SecretStore, Sendable {
    private let service: String
    private static let credentialsAccount = "credentials"
    private static let tokensAccount = "tokens"

    init(service: String = "com.florianmaisonnial.StravaLocal") {
        self.service = service
    }

    func credentials() -> StravaCredentials? {
        read(StravaCredentials.self, account: Self.credentialsAccount)
    }

    func save(_ credentials: StravaCredentials) throws {
        try write(credentials, account: Self.credentialsAccount)
    }

    func tokens() -> StravaTokens? {
        read(StravaTokens.self, account: Self.tokensAccount)
    }

    func save(_ tokens: StravaTokens) throws {
        try write(tokens, account: Self.tokensAccount)
    }

    func clearTokens() throws {
        try delete(account: Self.tokensAccount)
    }

    func clearAll() throws {
        try delete(account: Self.tokensAccount)
        try delete(account: Self.credentialsAccount)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read<T: Decodable>(_ type: T.Type, account: String) -> T? {
        var query = baseQuery(account: account)
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

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
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
}
