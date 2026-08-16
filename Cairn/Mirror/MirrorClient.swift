import Foundation

/// A value a mirrored row can hold. Explicit rather than `Any`, because the
/// rows are built in code and `JSONSerialization` on `Any` would let a wrong
/// type through to a 400 from PostgREST rather than to a compiler error.
enum MirrorValue: Sendable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case stringArray([String])
    case null

    /// The `JSONSerialization`-compatible form. A `Date` becomes an ISO 8601
    /// string with fractional seconds; a `Data` becomes base64, which is what
    /// PostgREST accepts for a `bytea` column.
    var jsonValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        case .date(let value): MirrorClient.iso8601.string(from: value)
        case .data(let value): value.base64EncodedString()
        case .stringArray(let values): values
        case .null: NSNull()
        }
    }
}

enum MirrorError: Error, Equatable {
    case notConfigured
    case unauthorized
    case http(status: Int, body: String)
    case transport(String)
}

protocol MirrorTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The same session-backed transport Strava uses. Its `send` already matches
/// `MirrorTransport`'s shape one-for-one, so this reuses the type rather than
/// declaring a second `URLSessionTransport` under a different name.
extension URLSessionTransport: MirrorTransport {}

/// All Supabase access: PostgREST rows and Storage objects, over `URLSession`.
/// Owns token refresh, on the pattern of `StravaClient`.
actor MirrorClient {
    private let store: SecretStore
    private let transport: MirrorTransport

    /// The refresh currently in flight, if any. Same reasoning as
    /// `StravaClient.refreshTask`: a second concurrent refresh would present
    /// a token another caller is already replacing, so everyone waits on the
    /// one task instead of racing.
    private var refreshTask: Task<MirrorSession, Error>?

    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` is not `Sendable`,
    /// but this instance is only ever read, never mutated after creation —
    /// the same justification `GPXWriter` uses for its own formatter.
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(store: SecretStore, transport: MirrorTransport = URLSessionTransport()) {
        self.store = store
        self.transport = transport
    }

    /// Whether an install has a project and a session on file. Decided purely
    /// from the store, never the network: a Mac that has never configured a
    /// mirror is an ordinary state, not a failure, and answering it must not
    /// wait on anything.
    var isConfigured: Bool {
        store.mirrorCredentials() != nil && store.mirrorSession() != nil
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        guard let credentials = store.mirrorCredentials() else {
            throw MirrorError.notConfigured
        }
        let request = try Self.authRequest(
            grantType: "password",
            body: ["email": email, "password": password],
            credentials: credentials
        )
        let (data, response) = try await send(request)
        try Self.checkStatus(response, data: data)
        let session = try Self.decodeSession(from: data)
        try store.save(session)
    }

    // MARK: - PostgREST

    func upsert(table: String, rows: [[String: MirrorValue]]) async throws {
        let credentials = try validCredentials()
        let token = try await validAccessToken(credentials: credentials)

        var request = URLRequest(
            url: credentials.projectURL.appendingPathComponent("rest/v1/\(table)")
        )
        request.httpMethod = "POST"
        request.setValue(credentials.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // `return=minimal`: rewriting rows we already hold client-side is
        // pure waste, and would double the traffic of every push for nothing.
        request.setValue(
            "resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: rows.map { row in row.mapValues { $0.jsonValue } }
        )

        let (data, response) = try await send(request)
        try Self.checkStatus(response, data: data)
    }

    // MARK: - Storage

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws {
        let credentials = try validCredentials()
        let token = try await validAccessToken(credentials: credentials)

        var request = URLRequest(
            url: credentials.projectURL.appendingPathComponent(
                "storage/v1/object/\(bucket)/\(path)"
            )
        )
        request.httpMethod = "POST"
        request.setValue(credentials.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // A replayed seed must not trip over what it already deposited.
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let (responseData, response) = try await send(request)
        try Self.checkStatus(response, data: responseData)
    }

    // MARK: - Plumbing

    private func validCredentials() throws -> MirrorCredentials {
        guard let credentials = store.mirrorCredentials() else {
            throw MirrorError.notConfigured
        }
        return credentials
    }

    /// Refreshes proactively when the stored session is expired, rather than
    /// reacting to a 401 — same choice as `StravaClient.validAccessToken`.
    private func validAccessToken(credentials: MirrorCredentials) async throws -> String {
        guard let session = store.mirrorSession() else { throw MirrorError.notConfigured }
        guard session.isExpired else { return session.accessToken }

        if let existing = refreshTask {
            return try await existing.value.accessToken
        }

        let transport = self.transport
        let store = self.store
        let task = Task<MirrorSession, Error> {
            try await Self.refresh(
                session: session, credentials: credentials, transport: transport, store: store
            )
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    /// Runs off the actor so the in-flight task can be awaited by several
    /// callers without any of them blocking the actor itself.
    private static func refresh(
        session: MirrorSession,
        credentials: MirrorCredentials,
        transport: MirrorTransport,
        store: SecretStore
    ) async throws -> MirrorSession {
        let request = try authRequest(
            grantType: "refresh_token",
            body: ["refresh_token": session.refreshToken],
            credentials: credentials
        )
        let (data, response) = try await Self.send(request, transport: transport)
        try checkStatus(response, data: data)
        let refreshed = try decodeSession(from: data)
        try store.save(refreshed)
        return refreshed
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Self.send(request, transport: transport)
    }

    /// Every transport call funnels through here, so a raw `URLSession`
    /// failure — offline, DNS, TLS — always reaches the caller as
    /// `MirrorError.transport` rather than as whatever `URLSession` threw.
    private static func send(
        _ request: URLRequest, transport: MirrorTransport
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as MirrorError {
            throw error
        } catch {
            throw MirrorError.transport(error.localizedDescription)
        }
    }

    private static func checkStatus(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw MirrorError.unauthorized
        default: throw MirrorError.http(status: response.statusCode, body: message(from: data))
        }
    }

    private static func authRequest(
        grantType: String, body: [String: String], credentials: MirrorCredentials
    ) throws -> URLRequest {
        var components = URLComponents(
            url: credentials.projectURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(credentials.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct AuthResponseDTO: Decodable {
        struct UserDTO: Decodable { let id: String }
        let access_token: String
        let refresh_token: String
        let expires_at: Double
        let user: UserDTO
    }

    private static func decodeSession(from data: Data) throws -> MirrorSession {
        guard let payload = try? JSONDecoder().decode(AuthResponseDTO.self, from: data) else {
            throw MirrorError.http(status: 0, body: "Réponse d'authentification illisible")
        }
        return MirrorSession(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date(timeIntervalSince1970: payload.expires_at),
            userID: payload.user.id
        )
    }

    private static func message(from data: Data) -> String {
        struct ErrorPayload: Decodable {
            let message: String?
            let error_description: String?
        }
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            if let message = payload.message { return message }
            if let description = payload.error_description { return description }
        }
        let raw = String(data: data, encoding: .utf8) ?? "erreur inconnue"
        return raw.count > 200 ? String(raw.prefix(200)) + "…" : raw
    }
}
