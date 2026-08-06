import Foundation

/// All Strava REST access. Owns token refresh and quota accounting so callers
/// never think about either.
actor StravaClient {
    private let store: SecretStore
    private let transport: HTTPTransport
    private let rateLimiter: RateLimiter

    private static let apiBase = URL(string: "https://www.strava.com/api/v3")!
    static let tokenEndpoint = URL(string: "https://www.strava.com/oauth/token")!
    private static let streamKeys = [
        "latlng", "altitude", "time", "heartrate", "cadence",
        "watts", "velocity_smooth", "temp", "grade_smooth", "moving",
    ]

    init(
        store: SecretStore,
        transport: HTTPTransport = URLSessionTransport(),
        rateLimiter: RateLimiter = RateLimiter()
    ) {
        self.store = store
        self.transport = transport
        self.rateLimiter = rateLimiter
    }

    var isAuthenticated: Bool { store.tokens() != nil }

    func rateLimitSnapshot() async -> RateLimitSnapshot? {
        await rateLimiter.snapshot
    }

    func signOut() throws { try store.clearTokens() }

    // MARK: - Endpoints

    func activities(
        after epoch: Int, page: Int, perPage: Int
    ) async throws -> [SummaryActivityDTO] {
        try await get(
            [SummaryActivityDTO].self, path: "athlete/activities",
            query: [
                "after": String(epoch), "page": String(page),
                "per_page": String(perPage),
            ]
        )
    }

    func activityDetail(id: Int64) async throws -> DetailActivityDTO {
        try await get(
            DetailActivityDTO.self, path: "activities/\(id)",
            query: ["include_all_efforts": "false"]
        )
    }

    func streams(id: Int64) async throws -> StreamSetDTO {
        try await get(
            StreamSetDTO.self, path: "activities/\(id)/streams",
            query: [
                "keys": Self.streamKeys.joined(separator: ","),
                "key_by_type": "true",
            ]
        )
    }

    func athlete() async throws -> AthleteDTO {
        try await get(AthleteDTO.self, path: "athlete", query: [:])
    }

    func gear(id: String) async throws -> GearDTO {
        try await get(GearDTO.self, path: "gear/\(id)", query: [:])
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(
        _ type: T.Type, path: String, query: [String: String]
    ) async throws -> T {
        let token = try await validAccessToken()

        let delay = await rateLimiter.delayBeforeNextRequest()
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }

        var components = URLComponents(
            url: Self.apiBase.appending(path: path), resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.send(request)
        let headers = response.allHeaderFields.reduce(into: [String: String]()) {
            if let key = $1.key as? String, let value = $1.value as? String {
                $0[key] = value
            }
        }

        switch response.statusCode {
        case 200..<300:
            await rateLimiter.observeSuccess(headers: headers)
            return try StravaJSON.decoder.decode(type, from: data)
        case 429:
            await rateLimiter.observeTooManyRequests()
            throw StravaError.http(429, "Quota d'API dépassé")
        default:
            throw StravaError.http(response.statusCode, Self.message(from: data))
        }
    }

    /// Refreshes proactively rather than reacting to a 401: Strava hands us an
    /// expiry, so a round trip can be skipped instead of wasted.
    private func validAccessToken() async throws -> String {
        guard let credentials = store.credentials() else {
            throw StravaError.missingCredentials
        }
        guard let tokens = store.tokens() else { throw StravaError.notAuthenticated }
        guard tokens.isExpired else { return tokens.accessToken }

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formBody([
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
        ])

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode),
              let payload = try? StravaJSON.decoder.decode(TokenResponseDTO.self, from: data)
        else {
            // A rejected refresh means the grant is gone for good; drop the
            // tokens so the UI can ask for a fresh sign-in, but keep the
            // credentials, which are still valid.
            try? store.clearTokens()
            throw StravaError.tokenRefreshRejected
        }

        let refreshed = StravaTokens(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date(timeIntervalSince1970: Double(payload.expires_at))
        )
        try store.save(refreshed)
        return refreshed.accessToken
    }

    static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func message(from data: Data) -> String {
        struct ErrorPayload: Decodable { let message: String? }
        return (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.message
            ?? String(data: data, encoding: .utf8)
            ?? "erreur inconnue"
    }
}
