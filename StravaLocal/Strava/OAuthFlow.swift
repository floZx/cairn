import Foundation
import Network
import AppKit

/// RFC 8252 loopback authorisation flow.
///
/// `ASWebAuthenticationSession` is deliberately not used: it can only complete
/// on a custom scheme or an https universal link, never on `http://localhost`,
/// which is the only callback shape Strava's "Authorization Callback Domain"
/// field accepts for a desktop app. Going through the default browser also
/// means the user's existing Strava session is already there.
actor OAuthFlow {
    private let store: SecretStore
    private let transport: HTTPTransport
    private static let scope = "read,activity:read_all,profile:read_all"

    init(store: SecretStore, transport: HTTPTransport = URLSessionTransport()) {
        self.store = store
        self.transport = transport
    }

    func authorize() async throws -> AthleteDTO? {
        guard let credentials = store.credentials() else {
            throw StravaError.missingCredentials
        }

        let listener = try LoopbackListener()
        let port = try listener.start()
        let state = UUID().uuidString

        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: credentials.clientID),
            .init(name: "redirect_uri", value: "http://localhost:\(port)/callback"),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: Self.scope),
            .init(name: "state", value: state),
        ]
        await MainActor.run { _ = NSWorkspace.shared.open(components.url!) }

        let callback = try await listener.waitForCallback()
        listener.stop()

        guard callback.state == state else { throw StravaError.oauthStateMismatch }
        if let error = callback.error { throw StravaError.oauthDenied(error) }
        guard let code = callback.code else { throw StravaError.oauthCancelled }

        return try await exchange(code: code, credentials: credentials)
    }

    private func exchange(
        code: String, credentials: StravaCredentials
    ) async throws -> AthleteDTO? {
        var request = URLRequest(url: StravaClient.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = StravaClient.formBody([
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
        ])

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw StravaError.http(response.statusCode, "échange du code impossible")
        }
        let payload = try StravaJSON.decoder.decode(TokenResponseDTO.self, from: data)
        try store.save(
            StravaTokens(
                accessToken: payload.access_token,
                refreshToken: payload.refresh_token,
                expiresAt: Date(timeIntervalSince1970: Double(payload.expires_at))
            )
        )
        return payload.athlete
    }
}

/// Minimal one-shot HTTP listener on the loopback interface. It parses exactly
/// one request line, answers a static page, and is done.
private final class LoopbackListener: @unchecked Sendable {
    struct Callback: Sendable {
        let code: String?
        let state: String?
        let error: String?
    }

    private let listener: NWListener
    private var continuation: CheckedContinuation<Callback, Error>?
    private let lock = NSLock()

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .global(qos: .userInitiated))

        // NWListener assigns the port asynchronously; poll briefly for it.
        for _ in 0..<200 {
            if let port = listener.port?.rawValue, port != 0 { return port }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw StravaError.oauthCancelled
    }

    func stop() {
        listener.cancel()
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let callback = Self.parse(requestLine: request)

            let body = callback.code != nil
                ? "<h2>Connexion réussie</h2><p>Vous pouvez fermer cet onglet et revenir à StravaLocal.</p>"
                : "<h2>Connexion refusée</h2><p>Revenez à StravaLocal pour réessayer.</p>"
            let response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Content-Length: \(body.utf8.count)\r
                Connection: close\r
                \r
                \(body)
                """
            connection.send(
                content: Data(response.utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )

            let pending = self.lock.withLock {
                let value = self.continuation
                self.continuation = nil
                return value
            }
            pending?.resume(returning: callback)
        }
    }

    private static func parse(requestLine: String) -> Callback {
        guard let line = requestLine.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(path)")
        else {
            return Callback(code: nil, state: nil, error: "requête illisible")
        }
        func item(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }
        return Callback(code: item("code"), state: item("state"), error: item("error"))
    }
}
