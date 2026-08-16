import Foundation
@testable import Cairn

/// A scriptable transport. The client — and everything above it — is tested
/// entirely without a network, which is also what lets the whole suite run
/// with no Supabase project in existence.
actor StubTransport: MirrorTransport {
    private var scripted: [(Data, HTTPURLResponse)]
    private let fallback: HTTPURLResponse?
    private var sent: [URLRequest] = []

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://x.supabase.co")!,
            statusCode: status, httpVersion: nil, headerFields: nil
        )!
    }

    /// Replies with a fixed script, then refuses. Use when the sequence matters.
    init(responses: [(Data, Int)]) {
        scripted = responses.map { ($0.0, Self.response($0.1)) }
        fallback = nil
    }

    /// Replies the same status to everything, forever. Use when only the
    /// requests sent are under test.
    init(alwaysRespondingWith status: Int) {
        scripted = []
        fallback = Self.response(status)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        if !scripted.isEmpty { return scripted.removeFirst() }
        guard let fallback else {
            throw MirrorError.transport("aucune réponse scriptée")
        }
        return (Data(), fallback)
    }

    func requests() -> [URLRequest] { sent }

    /// The tables written to, in the order they were written. `/rest/v1/activity`
    /// gives "activity".
    func tableOrder() -> [String] {
        sent.compactMap { request in
            guard let path = request.url?.path,
                  path.hasPrefix("/rest/v1/") else { return nil }
            return String(path.dropFirst("/rest/v1/".count))
        }
    }

    /// Every `uuid` sent to one table, across all requests.
    func upsertedUUIDs(table: String) -> [String] {
        sent.compactMap { request -> [String]? in
            guard request.url?.path == "/rest/v1/\(table)",
                  let body = request.httpBody,
                  let rows = try? JSONSerialization.jsonObject(with: body)
                      as? [[String: Any]]
            else { return nil }
            return rows.compactMap { $0["uuid"] as? String }
        }.flatMap { $0 }
    }
}

/// A secret store already holding a valid, unexpired mirror session.
func configuredStore() throws -> InMemorySecretStore {
    let store = InMemorySecretStore()
    try store.save(
        MirrorCredentials(
            projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
        )
    )
    try store.save(
        MirrorSession(
            accessToken: "jeton", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600), userID: "u"
        )
    )
    return store
}
