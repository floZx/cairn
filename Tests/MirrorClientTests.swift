import Testing
import Foundation
@testable import Cairn

@Suite("Client du miroir")
struct MirrorClientTests {
    /// Un upsert doit porter l'en-tête qui en fait un upsert. Sans lui,
    /// PostgREST refuse toute ligne déjà présente, et un push rejoué —
    /// c'est-à-dire le cas normal après une coupure — échouerait entièrement.
    @Test func lUpsertDemandeLaFusionDesDoublons() async throws {
        let transport = StubTransport(responses: [(Data(), 201)])
        let client = MirrorClient(store: try configuredStore(), transport: transport)

        try await client.upsert(
            table: "weight_entry",
            rows: [["uuid": .string("abc"), "kilograms": .double(70)]]
        )

        let sent = await transport.requests()
        #expect(sent.count == 1)
        let prefer = sent[0].value(forHTTPHeaderField: "Prefer") ?? ""
        #expect(prefer.contains("resolution=merge-duplicates"))
        #expect(sent[0].url?.path == "/rest/v1/weight_entry")
        #expect(sent[0].value(forHTTPHeaderField: "apikey") == "anon")
        #expect(sent[0].value(forHTTPHeaderField: "Authorization") == "Bearer jeton")
    }

    /// Sans identifiants, le client refuse tout de suite et proprement. C'est
    /// l'état d'une installation qui n'a jamais configuré de miroir, et c'est
    /// un cas ordinaire, pas une erreur.
    @Test func sansIdentifiantsLeClientRefuseSansReseau() async throws {
        let transport = StubTransport(responses: [])
        let client = MirrorClient(store: InMemorySecretStore(), transport: transport)

        await #expect(throws: MirrorError.notConfigured) {
            try await client.upsert(table: "weight_entry", rows: [])
        }
        #expect(await transport.requests().isEmpty)
    }

    /// Un 401 devient `unauthorized` et non une erreur HTTP générique : c'est le
    /// seul statut auquel l'appelant peut répondre par quelque chose d'utile,
    /// à savoir rafraîchir la session.
    @Test func unQuatreCentUnDevientUnRefusIdentifie() async throws {
        let transport = StubTransport(responses: [(Data(), 401)])
        let client = MirrorClient(store: try configuredStore(), transport: transport)

        await #expect(throws: MirrorError.unauthorized) {
            try await client.upsert(
                table: "weight_entry", rows: [["uuid": .string("a")]]
            )
        }
    }

    /// Des identifiants de projet sans session ne suffisent pas : configurer
    /// le projet et être connecté sont deux états distincts, et seul le
    /// second autorise une requête.
    @Test func avecIdentifiantsMaisSansSessionLeClientRefuseAussi() async throws {
        let store = InMemorySecretStore()
        try store.save(
            MirrorCredentials(
                projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
            )
        )
        let transport = StubTransport(responses: [])
        let client = MirrorClient(store: store, transport: transport)

        await #expect(throws: MirrorError.notConfigured) {
            try await client.upsert(table: "weight_entry", rows: [])
        }
        #expect(await transport.requests().isEmpty)
    }

    /// `isConfigured` répond depuis le trousseau seul, sans réseau.
    @Test func isConfiguredRefleteLaPresenceDesDeux() async throws {
        let complete = MirrorClient(
            store: try configuredStore(), transport: StubTransport(responses: [])
        )
        #expect(await complete.isConfigured)

        let empty = MirrorClient(
            store: InMemorySecretStore(), transport: StubTransport(responses: [])
        )
        #expect(await !empty.isConfigured)
    }

    /// Une session expirée est rafraîchie avant la requête qui en a besoin,
    /// et une seule fois : la réponse au rafraîchissement précède celle de
    /// l'upsert dans le script, et la requête suivante porte le jeton neuf.
    @Test func uneSessionExpireeEstRafraichieAvantLaRequete() async throws {
        let store = InMemorySecretStore()
        try store.save(
            MirrorCredentials(
                projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
            )
        )
        try store.save(
            MirrorSession(
                accessToken: "vieux", refreshToken: "r",
                expiresAt: Date().addingTimeInterval(-10), userID: "u"
            )
        )
        let refreshBody = try JSONSerialization.data(withJSONObject: [
            "access_token": "neuf", "refresh_token": "r2",
            "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
            "user": ["id": "u"],
        ])
        let transport = StubTransport(responses: [(refreshBody, 200), (Data(), 201)])
        let client = MirrorClient(store: store, transport: transport)

        try await client.upsert(table: "weight_entry", rows: [["uuid": .string("a")]])

        let sent = await transport.requests()
        #expect(sent.count == 2)
        #expect(sent[0].url?.path == "/auth/v1/token")
        #expect(sent[1].value(forHTTPHeaderField: "Authorization") == "Bearer neuf")
        #expect(store.mirrorSession()?.accessToken == "neuf")
    }

    /// `signIn` range la session obtenue au trousseau.
    @Test func signInRangeLaSessionObtenue() async throws {
        let store = InMemorySecretStore()
        try store.save(
            MirrorCredentials(
                projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
            )
        )
        let body = try JSONSerialization.data(withJSONObject: [
            "access_token": "a", "refresh_token": "r",
            "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
            "user": ["id": "u1"],
        ])
        let transport = StubTransport(responses: [(body, 200)])
        let client = MirrorClient(store: store, transport: transport)

        try await client.signIn(email: "a@b.co", password: "x")

        #expect(store.mirrorSession()?.accessToken == "a")
        #expect(store.mirrorSession()?.userID == "u1")
    }

    /// `upload` porte l'en-tête qui rend un amorçage rejouable sans buter sur
    /// ce qu'il a déjà déposé.
    @Test func uploadPorteLenTeteDeReecriture() async throws {
        let transport = StubTransport(responses: [(Data(), 200)])
        let client = MirrorClient(store: try configuredStore(), transport: transport)

        try await client.upload(
            bucket: "photos", path: "abc.jpg",
            data: Data([1, 2, 3]), contentType: "image/jpeg"
        )

        let sent = await transport.requests()
        #expect(sent.count == 1)
        #expect(sent[0].url?.path == "/storage/v1/object/photos/abc.jpg")
        #expect(sent[0].value(forHTTPHeaderField: "x-upsert") == "true")
        #expect(sent[0].value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(sent[0].httpBody == Data([1, 2, 3]))
    }

    /// Une panne de transport — hors ligne, DNS, TLS — devient
    /// `MirrorError.transport`, jamais l'exception d'origine : l'appelant n'a
    /// qu'un seul type d'erreur à traiter.
    @Test func unePanneDeTransportDevientUneErreurTypee() async throws {
        struct FailingTransport: MirrorTransport {
            struct Boom: Error {}
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                throw Boom()
            }
        }
        let client = MirrorClient(store: try configuredStore(), transport: FailingTransport())

        await #expect(throws: MirrorError.self) {
            try await client.upsert(
                table: "weight_entry", rows: [["uuid": .string("a")]]
            )
        }
    }
}
