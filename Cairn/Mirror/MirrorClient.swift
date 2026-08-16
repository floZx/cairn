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
        // NaN and infinity make `JSONSerialization` throw an Objective-C
        // exception Swift cannot catch — a crash, not an error. A pace or an
        // average speed is a division, so a non-finite result is not
        // theoretical; it becomes SQL NULL instead of taking the app down.
        case .double(let value): value.isFinite ? value : NSNull()
        case .bool(let value): value
        case .date(let value): MirrorClient.iso8601.string(from: value)
        case .data(let value): value.base64EncodedString()
        case .stringArray(let values): values
        case .null: NSNull()
        }
    }
}

enum MirrorError: LocalizedError, Sendable, Equatable {
    case notConfigured
    case unauthorized
    /// A refresh Supabase rejected, or one it accepted but that could not be
    /// saved. Either way the refresh token was single-use and is already
    /// spent, so the session is dead for good — distinct from `.unauthorized`
    /// so the caller knows to ask for a fresh sign-in rather than retry.
    case refreshRejected
    case http(status: Int, body: String)
    case transport(String)
    /// A row or auth body `JSONSerialization` refused. Not expected in
    /// practice — `MirrorValue` only holds encodable types — but a caller
    /// catching `MirrorError` must never see a raw Foundation error instead.
    case encodingFailed(String)
    /// A session obtained from Supabase that could not be written to the
    /// local secret store.
    case storageFailed(String)

    /// French, on the model of `StravaError.errorDescription` — without this,
    /// `error.localizedDescription` falls back to `NSError`'s generic English
    /// text ("The operation couldn't be completed…"), which is exactly what
    /// `MirrorProgress.statusText` would otherwise put in front of the user
    /// on the one indicator the plan concedes the mirror.
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Aucun projet Supabase n'est configuré. Renseignez son URL et sa clé dans les réglages."
        case .unauthorized:
            "Vous n'êtes pas connecté au miroir Supabase."
        case .refreshRejected:
            "La session Supabase a expiré ou a été révoquée. Reconnectez-vous."
        case let .http(status, body):
            "Supabase a répondu \(status) : \(body)"
        case let .transport(message):
            "Erreur réseau : \(message)"
        case let .encodingFailed(message):
            "Impossible d'encoder les données à envoyer : \(message)"
        case let .storageFailed(message):
            "Impossible d'enregistrer la session localement : \(message)"
        }
    }
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

    /// Whether a project is on file. Decided purely from the store, never the
    /// network: a Mac that has never configured a mirror is an ordinary
    /// state, not a failure, and answering it must not wait on anything.
    var isConfigured: Bool {
        store.mirrorCredentials() != nil
    }

    /// Whether a usable, unexpired session is on file — distinct from
    /// `isConfigured`: a project can be configured with nobody signed in
    /// yet, and callers such as the settings screen need to tell those two
    /// states apart (`isConfigured` gates the "enter a project" prompt,
    /// `isSignedIn` chooses between the signed-in and signed-out layouts).
    var isSignedIn: Bool {
        guard let session = store.mirrorSession() else { return false }
        return !session.isExpired
    }

    /// The signed-in user's identifier, for stamping every mirrored row's
    /// `user_id` — `nil` until a session is on file, expired or not: an
    /// engine that finds one nil should ask for sign-in, not push with a
    /// token about to be rejected anyway.
    var userID: String? {
        store.mirrorSession()?.userID
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
        do {
            try store.save(session)
        } catch {
            throw MirrorError.storageFailed(String(describing: error))
        }
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
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: rows.map { row in row.mapValues { $0.jsonValue } }
            )
        } catch {
            throw MirrorError.encodingFailed(String(describing: error))
        }

        let (data, response) = try await send(request)
        try Self.checkStatus(response, data: data)
    }

    /// Marks one row deleted rather than upserting it — the push's (task 9)
    /// counterpart to `upsert` above, used only for a tombstone.
    ///
    /// A `PATCH … ?uuid=eq.<uuid>`, never an upsert: four columns across the
    /// schema — `activity.start_date`, `activity.start_local_date`,
    /// `discarded_activity.discarded_at`, `discarded_activity.start_date` —
    /// are `not null` with no default, so an upsert of `{uuid, user_id,
    /// deleted_at}` on a row Supabase has never seen would attempt an
    /// `INSERT` and be rejected outright. That case is real: an object
    /// created and deleted in the same local transaction leaves a tombstone
    /// for a row that never made it out. A row update is the right semantics
    /// anyway — there is nothing to soft-delete on a row that does not
    /// exist — and a `PATCH` touching zero rows is exactly that: a
    /// non-event, not an error.
    ///
    /// The body carries only `{uuid, user_id, deleted_at}`, never the row
    /// itself: once a row is gone locally, nothing else about it has a
    /// source of truth left to send.
    func softDelete(table: String, uuid: String, userID: String) async throws {
        let credentials = try validCredentials()
        let token = try await validAccessToken(credentials: credentials)

        var components = URLComponents(
            url: credentials.projectURL.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "uuid", value: "eq.\(uuid)")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(credentials.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let row: [String: MirrorValue] = [
            "uuid": .string(uuid),
            "user_id": .string(userID),
            "deleted_at": .date(Date()),
        ]
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: row.mapValues { $0.jsonValue }
            )
        } catch {
            throw MirrorError.encodingFailed(String(describing: error))
        }

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
        guard (200..<300).contains(response.statusCode) else {
            // Supabase rotates the refresh token on every use: a rejected
            // refresh means the one just tried is already spent, so the
            // session is dead for good, not merely retryable — the same
            // reasoning as `StravaClient.refresh`. Drop it, but only if it's
            // still the one on file, so a concurrent success elsewhere isn't
            // undone.
            if store.mirrorSession()?.refreshToken == session.refreshToken {
                try? store.clearMirrorSession()
            }
            throw MirrorError.refreshRejected
        }
        let refreshed = try decodeSession(from: data)
        do {
            try store.save(refreshed)
        } catch {
            // The refresh token Supabase just returned was single-use; if it
            // can't be persisted, it's already gone from the server's point
            // of view too, and retrying would only hit the same rejection.
            // Fail the same way now instead of looping silently.
            if store.mirrorSession()?.refreshToken == session.refreshToken {
                try? store.clearMirrorSession()
            }
            throw MirrorError.refreshRejected
        }
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
        // `supabase-js` sends both `apikey` and a bearer `Authorization` on
        // every GoTrue call, and the Kong gateway in front of it can be
        // configured to require the second — without it, sign-in itself
        // could fail on a project set up that way.
        request.setValue("Bearer \(credentials.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw MirrorError.encodingFailed(String(describing: error))
        }
        return request
    }

    private struct AuthResponseDTO: Decodable {
        struct UserDTO: Decodable { let id: String }
        let access_token: String
        let refresh_token: String
        /// A GoTrue extension, not a standard OAuth field — absent on a
        /// strictly spec-following endpoint.
        let expires_at: Double?
        /// The field the OAuth spec actually guarantees; the fallback when
        /// `expires_at` is missing.
        let expires_in: Double?
        let user: UserDTO
    }

    private static func decodeSession(from data: Data) throws -> MirrorSession {
        guard let payload = try? JSONDecoder().decode(AuthResponseDTO.self, from: data)
        else {
            throw MirrorError.http(status: 0, body: "Réponse d'authentification illisible")
        }
        let expiresAt: Date
        if let epoch = payload.expires_at {
            expiresAt = Date(timeIntervalSince1970: epoch)
        } else if let seconds = payload.expires_in {
            expiresAt = Date().addingTimeInterval(seconds)
        } else {
            throw MirrorError.http(status: 0, body: "Réponse d'authentification illisible")
        }
        return MirrorSession(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: expiresAt,
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
