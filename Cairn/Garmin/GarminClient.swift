import Foundation

enum GarminError: LocalizedError, Sendable, Equatable {
    case notAuthenticated
    case invalidCredentials
    case mfaRejected
    case rateLimited
    /// Garmin's bot protection stopped the request: a 403, a CAPTCHA, an HTML
    /// page where JSON was expected.
    case blocked(String)
    case refreshRejected
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Vous n'êtes pas connecté à Garmin Connect."
        case .invalidCredentials:
            "Garmin a refusé l'adresse ou le mot de passe."
        case .mfaRejected:
            "Garmin a refusé le code de vérification."
        case .rateLimited:
            "Garmin limite les tentatives : réessayez dans quelques minutes."
        case let .blocked(detail):
            "Garmin a bloqué la connexion (\(detail)). Réessayez plus tard."
        case .refreshRejected:
            "La session Garmin a expiré. Reconnectez-vous dans les réglages."
        case .invalidResponse:
            "Réponse inattendue de Garmin."
        case let .http(status, message):
            "Garmin a répondu \(status) : \(message)"
        }
    }
}

/// A sign-in waiting for the code Garmin just sent.
///
/// Holds the very session that posted the password: the code is checked
/// against the SSO cookies that request set, so a fresh session would be
/// asking Garmin about a login it never saw.
final class GarminPendingLogin: Sendable {
    fileprivate let transport: HTTPTransport
    fileprivate let mfaMethod: String

    fileprivate init(transport: HTTPTransport, mfaMethod: String) {
        self.transport = transport
        self.mfaMethod = mfaMethod
    }
}

enum GarminLoginOutcome: Sendable {
    case connected(GarminTokens)
    case needsMFA(GarminPendingLogin)
}

/// Garmin Connect, through the endpoints its own iOS app uses.
///
/// Garmin has no public API for individuals. This is a port of the part of
/// `python-garminconnect` (0.3.16) that garmin-revisited relies on: the
/// mobile SSO login, the exchange of its service ticket for a DI OAuth2
/// token, and a handful of `connectapi` calls. Nothing here is documented by
/// Garmin, which may change any of it without notice; when that happens, the
/// library's `client.py` is where to look for what moved.
///
/// Only the library's first strategy is carried over. Its fallbacks exist to
/// get past TLS fingerprinting — `curl_cffi` impersonating Safari — and
/// `URLSession` on a Mac *is* an Apple TLS client, which is what they imitate.
actor GarminClient {
    private let store: SecretStore
    private let transport: HTTPTransport
    /// A login gets its own cookie jar, then throws it away. Injected so a
    /// test can script the SSO without a network.
    private let makeLoginTransport: @Sendable () -> HTTPTransport
    private var refreshTask: Task<GarminTokens, Error>?

    private static let sso = "https://sso.garmin.com"
    private static let connectAPI = URL(string: "https://connectapi.garmin.com")!
    private static let diTokenURL = URL(
        string: "https://diauth.garmin.com/di-oauth2-service/oauth/token"
    )!
    private static let diGrantType =
        "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket"
    private static let diClientIDs = [
        "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2",
        "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
        "GARMIN_CONNECT_MOBILE_ANDROID_DI",
        "GARMIN_CONNECT_MOBILE_IOS_DI",
    ]
    private static let iosClientID = "GCM_IOS_DARK"
    private static let iosServiceURL = "https://mobile.integration.garmin.com/gcm/ios"
    private static let portalClientID = "GarminConnect"
    private static let portalServiceURL = "https://connect.garmin.com/app"
    private static let iosLoginUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    /// The headers the Android app sends with every API call. The DI tokens
    /// are issued to that app, and `connectapi` checks the two agree.
    private static let nativeHeaders = [
        "User-Agent": "GCM-Android-5.23",
        "X-Garmin-User-Agent":
            "com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; "
            + "Android/33; Dalvik/2.1.0",
        "X-Garmin-Paired-App-Version": "10861",
        "X-Garmin-Client-Platform": "Android",
        "X-App-Ver": "10861",
        "X-Lang": "en",
        "X-GCExperience": "GC5",
        "Accept-Language": "en-US,en;q=0.9",
    ]

    init(
        store: SecretStore,
        transport: HTTPTransport = URLSessionTransport(session: GarminClient.apiSession()),
        makeLoginTransport: @escaping @Sendable () -> HTTPTransport = {
            URLSessionTransport(session: URLSession(configuration: .ephemeral))
        }
    ) {
        self.store = store
        self.transport = transport
        self.makeLoginTransport = makeLoginTransport
    }

    /// No cookies on API calls: authentication travels in the header, and a
    /// jar filling up with whatever Garmin sets back has nothing to add.
    static func apiSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    func signOut() throws { try store.clearGarminTokens() }

    // MARK: - Login

    func login(email: String, password: String) async throws -> GarminLoginOutcome {
        let session = makeLoginTransport()
        let body = try JSONSerialization.data(withJSONObject: [
            "username": email, "password": password,
            "rememberMe": true, "captchaToken": "",
        ])
        let (data, response) = try await session.send(
            Self.ssoRequest(path: "/mobile/api/login", flow: .mobile, body: body)
        )
        let result = try Self.ssoResult(data, response)

        switch result.type {
        case "MFA_REQUIRED":
            let method = (result.json["customerMfaInfo"] as? [String: Any])?[
                "mfaLastMethodUsed"
            ] as? String
            return .needsMFA(
                GarminPendingLogin(transport: session, mfaMethod: method ?? "email")
            )
        case "SUCCESSFUL":
            guard let ticket = result.json["serviceTicketId"] as? String else {
                throw GarminError.invalidResponse
            }
            return .connected(try await establishSession(ticket: ticket))
        case "INVALID_USERNAME_PASSWORD":
            throw GarminError.invalidCredentials
        case "CAPTCHA_REQUIRED":
            throw GarminError.blocked("CAPTCHA demandé")
        default:
            throw GarminError.blocked("réponse « \(result.type ?? "inconnue") »")
        }
    }

    /// Checks the code on the mobile endpoint, then on the portal one: they
    /// share the SSO cookies but not their rate limit, so the second can
    /// answer when the first has had enough.
    func verifyMFA(code: String, for pending: GarminPendingLogin) async throws -> GarminTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "mfaMethod": pending.mfaMethod,
            "mfaVerificationCode": code.trimmingCharacters(in: .whitespaces),
            "rememberMyBrowser": true,
            "reconsentList": [String](),
            "mfaSetup": false,
        ])
        var lastError: Error = GarminError.mfaRejected
        for (path, flow) in [
            ("/mobile/api/mfa/verifyCode", SSOFlow.mobile),
            ("/portal/api/mfa/verifyCode", SSOFlow.portal),
        ] {
            do {
                let (data, response) = try await pending.transport.send(
                    Self.ssoRequest(path: path, flow: flow, body: body)
                )
                let result = try Self.ssoResult(data, response)
                guard result.type == "SUCCESSFUL",
                      let ticket = result.json["serviceTicketId"] as? String
                else {
                    lastError = GarminError.mfaRejected
                    continue
                }
                // The ticket is bound to the service the login named, and the
                // login always named the iOS one.
                return try await establishSession(ticket: ticket)
            } catch let error as GarminError where error != .invalidCredentials {
                lastError = error
            }
        }
        throw lastError
    }

    private enum SSOFlow { case mobile, portal }

    private static func ssoRequest(path: String, flow: SSOFlow, body: Data) -> URLRequest {
        var components = URLComponents(string: sso + path)!
        components.queryItems = [
            URLQueryItem(name: "clientId", value: flow == .mobile ? iosClientID : portalClientID),
            URLQueryItem(name: "locale", value: "en-US"),
            URLQueryItem(name: "service", value: flow == .mobile ? iosServiceURL : portalServiceURL),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(iosLoginUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sso, forHTTPHeaderField: "Origin")
        return request
    }

    private struct SSOResult {
        let json: [String: Any]
        var type: String? { (json["responseStatus"] as? [String: Any])?["type"] as? String }
    }

    private static func ssoResult(_ data: Data, _ response: HTTPURLResponse) throws -> SSOResult {
        if response.statusCode == 429 { throw GarminError.rateLimited }
        if response.statusCode == 403 { throw GarminError.blocked("HTTP 403") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GarminError.blocked("HTTP \(response.statusCode), pas de JSON")
        }
        if (json["error"] as? [String: Any])?["status-code"] as? String == "429" {
            throw GarminError.rateLimited
        }
        return SSOResult(json: json)
    }

    /// Trades the SSO's one-time ticket for a DI token, trying each client id
    /// the library knows until Garmin accepts one, then checks the API takes
    /// it — the auth host can issue a token `connectapi` then refuses.
    private func establishSession(ticket: String) async throws -> GarminTokens {
        var issued: GarminTokens?
        for clientID in Self.diClientIDs {
            let request = Self.tokenRequest(clientID: clientID, form: [
                "client_id": clientID,
                "service_ticket": ticket,
                "grant_type": Self.diGrantType,
                "service_url": Self.iosServiceURL,
            ])
            let (data, response) = try await transport.send(request)
            if response.statusCode == 429 { throw GarminError.rateLimited }
            guard (200..<300).contains(response.statusCode),
                  let tokens = Self.tokens(from: data, fallbackClientID: clientID)
            else { continue }
            issued = tokens
            break
        }
        guard var tokens = issued else {
            throw GarminError.blocked("échange du ticket refusé")
        }
        try store.save(tokens)
        let profile = try await getJSON("/userprofile-service/socialProfile") as? [String: Any]
        tokens.displayName = (profile?["fullName"] as? String) ?? (profile?["displayName"] as? String)
        try store.save(tokens)
        return tokens
    }

    private static func tokenRequest(clientID: String, form: [String: String]) -> URLRequest {
        var request = URLRequest(url: diTokenURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        for (key, value) in nativeHeaders { request.setValue(value, forHTTPHeaderField: key) }
        let basic = Data("\(clientID):".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.httpBody = Data(formEncoded(form).utf8)
        return request
    }

    static func formEncoded(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    private static func tokens(
        from data: Data, fallbackClientID: String, previous: GarminTokens? = nil
    ) -> GarminTokens? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { return nil }
        let refresh = (json["refresh_token"] as? String) ?? previous?.refreshToken ?? ""
        let clientID = (GarminJWT.claims(access)?["client_id"] as? String) ?? fallbackClientID
        return GarminTokens(
            accessToken: access, refreshToken: refresh, clientID: clientID,
            displayName: previous?.displayName
        )
    }

    // MARK: - Tokens

    private func validTokens() async throws -> GarminTokens {
        guard let tokens = store.garminTokens() else { throw GarminError.notAuthenticated }
        return tokens.expiresSoon ? try await refresh() : tokens
    }

    /// One refresh at a time: Garmin may rotate the refresh token, and a
    /// second refresh would present the one the first just used up.
    private func refresh() async throws -> GarminTokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> GarminTokens {
        guard let current = store.garminTokens(), !current.refreshToken.isEmpty else {
            throw GarminError.notAuthenticated
        }
        let request = Self.tokenRequest(clientID: current.clientID, form: [
            "grant_type": "refresh_token",
            "client_id": current.clientID,
            "refresh_token": current.refreshToken,
        ])
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode),
              let tokens = Self.tokens(
                  from: data, fallbackClientID: current.clientID, previous: current
              )
        else {
            // A refused refresh token is a dead session: keeping it would
            // only have every later call fail the same way, more slowly.
            if (400..<500).contains(response.statusCode) {
                try? store.clearGarminTokens()
                throw GarminError.refreshRejected
            }
            throw GarminError.http(response.statusCode, Self.snippet(data))
        }
        try store.save(tokens)
        return tokens
    }

    // MARK: - API

    /// Activities started between the two days, newest first.
    func activities(from start: Date, to end: Date, limit: Int = 50) async throws -> [GarminActivity] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let json = try await getJSON(
            "/activitylist-service/activities/search/activities",
            query: [
                "startDate": day.string(from: start), "endDate": day.string(from: end),
                "start": "0", "limit": String(limit),
            ]
        )
        return (json as? [[String: Any]] ?? []).compactMap(GarminActivity.init(json:))
    }

    func activity(id: Int64) async throws -> GarminActivity {
        guard let json = try await getJSON("/activity-service/activity/\(id)") as? [String: Any],
              let activity = GarminActivity(json: json)
        else { throw GarminError.invalidResponse }
        return activity
    }

    /// The heart-rate and power zones Garmin applied to one activity, as they
    /// stood that day — not today's, which is the whole point.
    func zones(activityID id: Int64) async throws -> GarminZones {
        let hr = try await getJSON("/activity-service/activity/\(id)/hrTimeInZones")
        let power = try await getJSON("/activity-service/activity/\(id)/powerTimeInZones")
        return GarminZones(heartRateJSON: hr, powerJSON: power)
    }

    func activityTypes() async throws -> [GarminActivityType] {
        let json = try await getJSON("/activity-service/activity/activityTypes")
        return (json as? [[String: Any]] ?? []).compactMap(GarminActivityType.init(json:))
    }

    func gear(forActivity id: Int64) async throws -> [GarminGear] {
        let json = try await getJSON(
            "/gear-service/gear/filterGear", query: ["activityId": String(id)]
        )
        return (json as? [[String: Any]] ?? []).compactMap(GarminGear.init(json:))
    }

    /// Every piece of gear on the account, retired included: an old pair of
    /// shoes may still be what an old run was done in.
    func allGear() async throws -> [GarminGear] {
        let settings = try await getJSON(
            "/userprofile-service/userprofile/user-settings"
        ) as? [String: Any]
        guard let profile = settings?["id"] as? Int64 ?? (settings?["id"] as? Int).map(Int64.init)
        else { throw GarminError.invalidResponse }
        let json = try await getJSON(
            "/gear-service/gear/filterGear", query: ["userProfilePk": String(profile)]
        )
        return (json as? [[String: Any]] ?? []).compactMap(GarminGear.init(json:))
    }

    /// Only the fields passed are sent; Garmin leaves the others as they are.
    func updateActivity(
        id: Int64, name: String?, description: String?, type: GarminActivityType?
    ) async throws {
        var payload: [String: Any] = ["activityId": id]
        if let name { payload["activityName"] = name }
        if let description { payload["description"] = description }
        if let type {
            payload["activityTypeDTO"] = [
                "typeId": type.typeID, "typeKey": type.typeKey,
                "parentTypeId": type.parentTypeID,
            ]
        }
        guard payload.count > 1 else { return }
        _ = try await send(
            "PUT", "/activity-service/activity/\(id)",
            body: try JSONSerialization.data(withJSONObject: payload)
        )
    }

    func link(gear uuid: String, toActivity id: Int64) async throws {
        _ = try await send("PUT", "/gear-service/gear/link/\(uuid)/activity/\(id)")
    }

    func unlink(gear uuid: String, fromActivity id: Int64) async throws {
        _ = try await send("PUT", "/gear-service/gear/unlink/\(uuid)/activity/\(id)")
    }

    /// Links and unlinks until the activity carries exactly `wanted`.
    func setGear(_ wanted: [String], current: [GarminGear], activityID id: Int64) async throws {
        let present = Set(current.map(\.uuid))
        for uuid in present.subtracting(wanted) {
            try await unlink(gear: uuid, fromActivity: id)
        }
        for uuid in Set(wanted).subtracting(present) {
            try await link(gear: uuid, toActivity: id)
        }
    }

    private func getJSON(_ path: String, query: [String: String] = [:]) async throws -> Any? {
        let data = try await send("GET", path, query: query)
        return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data)
    }

    private func send(
        _ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil
    ) async throws -> Data {
        var tokens = try await validTokens()
        for attempt in 0..<2 {
            var components = URLComponents(
                url: Self.connectAPI.appending(path: path), resolvingAgainstBaseURL: false
            )!
            if !query.isEmpty {
                components.queryItems = query.sorted { $0.key < $1.key }
                    .map { URLQueryItem(name: $0.key, value: $0.value) }
            }
            var request = URLRequest(url: components.url!, timeoutInterval: 20)
            request.httpMethod = method
            for (key, value) in Self.nativeHeaders { request.setValue(value, forHTTPHeaderField: key) }
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let (data, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300:
                return data
            case 401 where attempt == 0:
                tokens = try await refresh()
            case 429:
                throw GarminError.rateLimited
            default:
                throw GarminError.http(response.statusCode, Self.snippet(data))
            }
        }
        throw GarminError.notAuthenticated
    }

    private static func snippet(_ data: Data) -> String {
        String(decoding: data.prefix(200), as: UTF8.self)
    }
}
