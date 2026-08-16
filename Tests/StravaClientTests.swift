import Testing
import Foundation
@testable import Cairn

/// Records requests and replays canned responses in order.
private final class StravaStubTransport: HTTPTransport, @unchecked Sendable {
    struct Response { let status: Int; let body: Data; let headers: [String: String] }

    private let lock = NSLock()
    private var queue: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) { queue = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            requests.append(request)
            let response = queue.isEmpty ? Response(status: 500, body: Data(), headers: [:])
                                         : queue.removeFirst()
            let http = HTTPURLResponse(
                url: request.url!, statusCode: response.status,
                httpVersion: nil, headerFields: response.headers
            )!
            return (response.body, http)
        }
    }
}

private func json(_ string: String) -> Data { Data(string.utf8) }

private let quotaHeaders = [
    "X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "1,1",
]

@Suite("StravaClient")
struct StravaClientTests {
    private func validStore() -> InMemorySecretStore {
        InMemorySecretStore(
            credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
            tokens: StravaTokens(
                accessToken: "good", refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600)
            )
        )
    }

    @Test("sans credentials, l'appel échoue avant tout réseau")
    func requiresCredentials() async {
        let transport = StravaStubTransport([])
        let client = StravaClient(store: InMemorySecretStore(), transport: transport)
        await #expect(throws: StravaError.self) {
            _ = try await client.athlete()
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("la liste d'activités passe after, page et per_page et porte le jeton")
    func buildsActivityRequest() async throws {
        let transport = StravaStubTransport([
            .init(status: 200, body: json("[]"), headers: quotaHeaders)
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        let result = try await client.activities(after: 1_700_000_000, page: 2, perPage: 200)

        #expect(result.isEmpty)
        let url = transport.requests[0].url!.absoluteString
        #expect(url.contains("/api/v3/athlete/activities"))
        #expect(url.contains("after=1700000000"))
        #expect(url.contains("page=2"))
        #expect(url.contains("per_page=200"))
        #expect(
            transport.requests[0].value(forHTTPHeaderField: "Authorization")
                == "Bearer good"
        )
    }

    @Test("les streams demandent toutes les clés en une requête")
    func requestsAllStreamKeys() async throws {
        let transport = StravaStubTransport([
            .init(
                status: 200,
                body: json(#"{"altitude":{"data":[1.0,2.0]}}"#),
                headers: quotaHeaders
            )
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        let streams = try await client.streams(id: 99)

        #expect(streams.altitude?.data == [1, 2])
        let url = transport.requests[0].url!.absoluteString
        #expect(url.contains("/api/v3/activities/99/streams"))
        #expect(url.contains("key_by_type=true"))
        #expect(url.contains("latlng"))
        #expect(url.contains("heartrate"))
        #expect(url.contains("watts"))
    }

    @Test("un jeton expiré est rafraîchi avant l'appel, puis persisté")
    func refreshesExpiredToken() async throws {
        let store = InMemorySecretStore(
            credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
            tokens: StravaTokens(
                accessToken: "stale", refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(-60)
            )
        )
        let transport = StravaStubTransport([
            .init(
                status: 200,
                body: json(
                    #"{"access_token":"fresh","refresh_token":"r2","expires_at":4000000000}"#
                ),
                headers: [:]
            ),
            .init(status: 200, body: json("[]"), headers: quotaHeaders),
        ])
        let client = StravaClient(store: store, transport: transport)
        _ = try await client.activities(after: 0, page: 1, perPage: 200)

        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].url!.absoluteString.contains("/oauth/token"))
        #expect(
            transport.requests[1].value(forHTTPHeaderField: "Authorization")
                == "Bearer fresh"
        )
        #expect(store.tokens()?.accessToken == "fresh")
        #expect(store.tokens()?.refreshToken == "r2")
    }

    @Test("un refresh refusé purge les jetons sans toucher aux credentials")
    func clearsTokensOnRejectedRefresh() async {
        let store = InMemorySecretStore(
            credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
            tokens: StravaTokens(
                accessToken: "stale", refreshToken: "revoked",
                expiresAt: Date().addingTimeInterval(-60)
            )
        )
        let transport = StravaStubTransport([
            .init(status: 401, body: json(#"{"message":"Unauthorized"}"#), headers: [:])
        ])
        let client = StravaClient(store: store, transport: transport)

        await #expect(throws: StravaError.tokenRefreshRejected) {
            _ = try await client.athlete()
        }
        #expect(store.tokens() == nil)
        #expect(store.credentials() != nil)
    }

    @Test("une erreur HTTP est remontée avec son code")
    func surfacesHTTPErrors() async {
        let transport = StravaStubTransport([
            .init(status: 404, body: json(#"{"message":"Record Not Found"}"#), headers: [:])
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        await #expect(throws: StravaError.http(404, "Record Not Found")) {
            _ = try await client.activityDetail(id: 1)
        }
    }

    @Test("le quota lu dans les en-têtes est exposé")
    func exposesQuota() async throws {
        let transport = StravaStubTransport([
            .init(
                status: 200, body: json("[]"),
                headers: ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "17,342"]
            )
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        _ = try await client.activities(after: 0, page: 1, perPage: 200)
        let snapshot = await client.rateLimitSnapshot()
        #expect(snapshot?.shortTermUsage == 17)
        #expect(snapshot?.dailyUsage == 342)
    }

    @Test("un 429 est signalé au limiteur sans passer par le chemin de succès")
    func reportsThrottlingToRateLimiter() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        let transport = StravaStubTransport([
            .init(
                status: 429, body: json(#"{"message":"Rate Limit Exceeded"}"#),
                headers: quotaHeaders
            )
        ])
        let client = StravaClient(
            store: validStore(), transport: transport, rateLimiter: limiter
        )

        await #expect(throws: StravaError.http(429, "Quota d'API dépassé")) {
            _ = try await client.athlete()
        }
        // A throttle must produce a wait, and must not record the quota headers
        // as if the call had succeeded.
        #expect(await limiter.delayBeforeNextRequest() > 0)
        #expect(await limiter.snapshot == nil)
    }
}
