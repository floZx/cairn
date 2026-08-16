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

    /// `isConfigured` répond de la seule présence d'un projet, sans réseau.
    /// Un install qui a saisi l'URL et la clé mais n'a jamais signé de
    /// session doit rester « configuré » : `AccountSettingsView` en a besoin
    /// pour proposer le bouton de connexion plutôt que le griser comme sur
    /// une installation vierge.
    @Test func isConfiguredNeDependQueDuProjetPasDeLaSession() async throws {
        let store = InMemorySecretStore()
        try store.save(
            MirrorCredentials(
                projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
            )
        )
        let client = MirrorClient(store: store, transport: StubTransport(responses: []))
        #expect(await client.isConfigured)
        #expect(await !client.isSignedIn)

        let empty = MirrorClient(
            store: InMemorySecretStore(), transport: StubTransport(responses: [])
        )
        #expect(await !empty.isConfigured)
        #expect(await !empty.isSignedIn)
    }

    /// `isSignedIn` exige une session sur le trousseau, non expirée.
    @Test func isSignedInExigeUneSessionValide() async throws {
        let client = MirrorClient(
            store: try configuredStore(), transport: StubTransport(responses: [])
        )
        #expect(await client.isConfigured)
        #expect(await client.isSignedIn)
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

    /// Les huit cas de `MirrorValue` traversent `JSONSerialization` sans
    /// perte ni surprise. C'est le contrat le plus littéral du brief, et
    /// sept tâches à venir en dépendent sans jamais le revérifier
    /// elles-mêmes : c'est ici ou nulle part.
    @Test func lesHuitCasDeMirrorValueEncodentCorrectement() async throws {
        let transport = StubTransport(responses: [(Data(), 201)])
        let client = MirrorClient(store: try configuredStore(), transport: transport)
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        let bytes = Data([0x01, 0x02, 0x03])

        try await client.upsert(
            table: "weight_entry",
            rows: [[
                "a": .string("abc"),
                "b": .int(42),
                "c": .double(3.5),
                "d": .bool(true),
                "e": .date(date),
                "f": .data(bytes),
                "g": .stringArray(["x", "y"]),
                "h": .null,
            ]]
        )

        let sent = await transport.requests()
        let body = try #require(sent[0].httpBody)
        let rows = try #require(
            JSONSerialization.jsonObject(with: body) as? [[String: Any]]
        )
        let row = try #require(rows.first)

        #expect(row["a"] as? String == "abc")
        #expect(row["b"] as? Int64 == 42)
        #expect(row["c"] as? Double == 3.5)
        #expect(row["d"] as? Bool == true)
        #expect(row["e"] as? String == MirrorClient.iso8601.string(from: date))
        #expect(row["f"] as? String == bytes.base64EncodedString())
        #expect(row["g"] as? [String] == ["x", "y"])
        #expect(row["h"] is NSNull)
    }

    /// Un `Double` non fini — NaN ou infini, ce qu'une vitesse moyenne ou une
    /// allure calculées par division peuvent produire dès la tâche 6 — ne
    /// doit jamais planter le miroir. `JSONSerialization` lève une exception
    /// Objective-C non rattrapable sur un tel nombre : sans ce garde-fou,
    /// c'est un plantage, pas une erreur, et cela contredirait la garantie
    /// que l'échec du miroir reste un simple indicateur.
    @Test func unDoubleNonFiniDevientNull() async throws {
        let transport = StubTransport(responses: [(Data(), 201)])
        let client = MirrorClient(store: try configuredStore(), transport: transport)

        try await client.upsert(
            table: "weight_entry",
            rows: [["speed": .double(.nan), "pace": .double(.infinity)]]
        )

        let sent = await transport.requests()
        let body = try #require(sent[0].httpBody)
        let row = try #require(
            (JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first
        )
        #expect(row["speed"] is NSNull)
        #expect(row["pace"] is NSNull)
    }

    /// `signIn` porte aussi `Authorization: Bearer <anonKey>` sur l'appel
    /// GoTrue, en plus d'`apikey` : la passerelle Kong peut l'exiger selon la
    /// configuration du projet, et sans lui la toute première connexion
    /// échouerait.
    @Test func signInPorteAussiLenTeteAuthorization() async throws {
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

        let sent = await transport.requests()
        #expect(sent[0].value(forHTTPHeaderField: "Authorization") == "Bearer anon")
    }

    /// `expires_in` est le champ OAuth standard ; `expires_at` est une
    /// extension GoTrue qui peut manquer. Sans repli, une réponse qui ne
    /// porte que `expires_in` échouerait à décoder une session pourtant
    /// valide.
    @Test func expiresInSertDeRepliQuandExpiresAtManque() async throws {
        let store = InMemorySecretStore()
        try store.save(
            MirrorCredentials(
                projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
            )
        )
        let body = try JSONSerialization.data(withJSONObject: [
            "access_token": "a", "refresh_token": "r",
            "expires_in": 3600, "user": ["id": "u1"],
        ])
        let transport = StubTransport(responses: [(body, 200)])
        let client = MirrorClient(store: store, transport: transport)

        try await client.signIn(email: "a@b.co", password: "x")

        let session = store.mirrorSession()
        #expect(session?.accessToken == "a")
        #expect(session?.isExpired == false)
    }

    /// Un rafraîchissement refusé lève un cas distinct de `.unauthorized` —
    /// l'appelant doit savoir qu'il faut redemander une connexion, pas
    /// rejouer indéfiniment le même échec — et jette le jeton mort sans
    /// toucher aux identifiants du projet : ce n'est pas eux qui sont en
    /// cause.
    @Test func unRafraichissementRefuseViseLaSessionPasLesIdentifiants() async throws {
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
        let transport = StubTransport(responses: [(Data(), 401)])
        let client = MirrorClient(store: store, transport: transport)

        await #expect(throws: MirrorError.refreshRejected) {
            try await client.upsert(
                table: "weight_entry", rows: [["uuid": .string("a")]]
            )
        }
        #expect(store.mirrorSession() == nil)
        #expect(store.mirrorCredentials() != nil)
    }
}
