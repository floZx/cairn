import Foundation
import Network
import AppKit
import os

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
    /// Long enough for a real person to read a consent screen, short enough that
    /// an abandoned flow eventually releases the port.
    private static let timeout: Duration = .seconds(300)

    init(store: SecretStore, transport: HTTPTransport = URLSessionTransport()) {
        self.store = store
        self.transport = transport
    }

    func authorize() async throws -> AthleteDTO? {
        guard let credentials = store.credentials() else {
            throw StravaError.missingCredentials
        }

        let listener = try LoopbackListener()
        // Covers every exit: success, throw, and task cancellation.
        defer { listener.stop() }

        let port = try await listener.start()
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
        let authorizationURL = components.url!

        let opened = await MainActor.run { NSWorkspace.shared.open(authorizationURL) }
        guard opened else { throw StravaError.browserLaunchFailed }

        let callback = try await listener.waitForCallback(timeout: Self.timeout)

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

/// Minimal one-shot HTTP listener on the loopback interface.
///
/// Only a request that actually carries OAuth parameters resolves the wait.
/// Browsers routinely open speculative connections and fetch `/favicon.ico`, and
/// letting one of those resolve a one-shot wait would drop the real redirect.
private final class LoopbackListener: @unchecked Sendable {
    struct Callback: Sendable {
        let code: String?
        let state: String?
        let error: String?
    }

    private let listener: NWListener
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Callback, Error>?
    /// Holds a callback that arrived before anyone was waiting for it.
    private var bufferedCallback: Callback?
    private var isFinished = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
    }

    /// Waits for the listener to be ready and returns the port the OS assigned.
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                // stateUpdateHandler can fire more than once; resume only once.
                let alreadyResumed = resumed.withLock { value -> Bool in
                    if value { return true }
                    switch state {
                    case .ready, .failed, .cancelled: value = true; return false
                    default: return true
                    }
                }
                if alreadyResumed { return }

                switch state {
                case .ready:
                    continuation.resume(returning: self.listener.port?.rawValue ?? 0)
                case let .failed(error):
                    continuation.resume(
                        throwing: StravaError.loopbackUnavailable(error.localizedDescription)
                    )
                case .cancelled:
                    continuation.resume(
                        throwing: StravaError.loopbackUnavailable("listener annulé")
                    )
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        guard port != 0 else {
            throw StravaError.loopbackUnavailable("aucun port attribué")
        }
        return port
    }

    func stop() {
        listener.cancel()
        // Anyone still waiting must not wait forever.
        finish(with: .failure(StravaError.oauthCancelled))
    }

    /// Resolves with the first OAuth callback, or throws on timeout or cancellation.
    func waitForCallback(timeout: Duration) async throws -> Callback {
        try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask { try await self.awaitCallback() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw StravaError.oauthTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw StravaError.oauthCancelled
            }
            return result
        }
    }

    private func awaitCallback() async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediate: Result<Callback, Error>? = lock.withLock {
                    if let buffered = bufferedCallback {
                        bufferedCallback = nil
                        isFinished = true
                        return .success(buffered)
                    }
                    if isFinished { return .failure(StravaError.oauthCancelled) }
                    self.continuation = continuation
                    return nil
                }
                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            finish(with: .failure(StravaError.oauthCancelled))
        }
    }

    /// Delivers exactly once: to a waiter if there is one, otherwise buffered.
    private func deliver(_ callback: Callback) {
        let waiter: CheckedContinuation<Callback, Error>? = lock.withLock {
            guard !isFinished else { return nil }
            if let waiting = continuation {
                continuation = nil
                isFinished = true
                return waiting
            }
            bufferedCallback = callback
            return nil
        }
        waiter?.resume(returning: callback)
    }

    private func finish(with result: Result<Callback, Error>) {
        let waiter: CheckedContinuation<Callback, Error>? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true
            let waiting = continuation
            continuation = nil
            return waiting
        }
        waiter?.resume(with: result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let callback = Self.parse(requestLine: request)

            let isOAuthCallback = callback != nil
            let body = isOAuthCallback
                ? "<h2>Connexion réussie</h2><p>Vous pouvez fermer cet onglet et revenir à Cairn.</p>"
                : "<h2>Cairn</h2><p>En attente de l'autorisation Strava…</p>"
            // no-store keeps the URL bearing the authorization code out of history.
            let response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Content-Length: \(body.utf8.count)\r
                Cache-Control: no-store\r
                Connection: close\r
                \r
                \(body)
                """
            connection.send(
                content: Data(response.utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )

            // A speculative connection or a favicon fetch carries no OAuth
            // parameters; answering it must not resolve the wait.
            if let callback {
                self.deliver(callback)
            }
        }
    }

    /// Returns nil for anything that is not an OAuth callback.
    private static func parse(requestLine: String) -> Callback? {
        guard let line = requestLine.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(path)")
        else { return nil }

        func item(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }
        let code = item("code")
        let state = item("state")
        let error = item("error")
        guard code != nil || state != nil || error != nil else { return nil }
        return Callback(code: code, state: state, error: error)
    }
}
