import Foundation
import SwiftData
import Testing
@testable import Cairn

/// Le journal chiffré à travers le miroir : les deux cas où se tromper coûte
/// une note — tirée sans la clé, envoyée en clair.
@Suite("Miroir : le journal chiffré")
@MainActor
struct MirrorJournalCipherTests {
    private static let phrase = "une phrase d'essai"
    private static let sel = Data("sel-de-seize-oct".utf8)
    /// Peu d'itérations : le calcul se vérifie ailleurs, ici il ne fait que ralentir.
    private static let cle = JournalCipher.deriveKey(passphrase: phrase, salt: sel, iterations: 1000)
    private static let chiffre = JournalCipher(key: cle)

    private static func configBody() throws -> Data {
        let config = JournalCryptoConfig(
            salt: sel.base64EncodedString(), iterations: 1000, verifier: try chiffre.makeVerifier()
        )
        return try JSONEncoder().encode([config])
    }

    private static func page(text: String) -> Data {
        let row: [String: Any] = [
            "uuid": "n1", "date_key_raw": "2026-09-26", "text": text,
            "updated_at": "2026-09-26T10:00:00+00:00",
            "edited_at": "2026-09-26T10:00:00+00:00", "deleted_at": NSNull(),
        ]
        return try! JSONSerialization.data(withJSONObject: [row])
    }

    private static func store(avecCle: Bool) throws -> InMemorySecretStore {
        let store = try configuredStore()
        if avecCle {
            try store.save(JournalKey(keyData: chiffre.keyData, salt: sel.base64EncodedString()))
        }
        return store
    }

    /// Sans la clé, une note chiffrée n'écrit rien — ni du charabia, ni du
    /// vide par-dessus la note du Mac — et le curseur reste avant elle.
    @Test func sansLaCleRienNEstEcritNiLu() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [
                (Self.page(text: try Self.chiffre.seal("Secret du jour")), 200),
                (try Self.configBody(), 200),
            ],
            thenAlways: Data("[]".utf8)
        )
        let engine = MirrorEngine(
            client: MirrorClient(store: try Self.store(avecCle: false), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.pull()

        #expect(try ModelContext(container).fetch(FetchDescriptor<JournalNote>()).isEmpty)
        #expect(cursor.lastPulledAt(for: "journal_note") == nil)
    }

    @Test func avecLaCleLaNoteArriveEnClair() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [
                (Self.page(text: try Self.chiffre.seal("Secret du jour")), 200),
                (try Self.configBody(), 200),
            ],
            thenAlways: Data("[]".utf8)
        )
        let engine = MirrorEngine(
            client: MirrorClient(store: try Self.store(avecCle: true), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.pull()

        let notes = try ModelContext(container).fetch(FetchDescriptor<JournalNote>())
        #expect(notes.map(\.text) == ["Secret du jour"])
    }

    /// Envoyée chiffrée, sans étiquettes lisibles à côté.
    @Test func lAmorcageEnvoieLesNotesChiffrees() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(JournalNote(dateKey: DateKey(raw: "2026-09-26")!, text: "Course avec @Sam #PI"))
        try context.save()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [(try Self.configBody(), 200)], thenAlways: Data(), status: 201
        )
        let engine = MirrorEngine(
            client: MirrorClient(store: try Self.store(avecCle: true), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.bootstrap()

        let envoi = try #require(await transport.requests().first {
            $0.url?.path == "/rest/v1/journal_note" && $0.httpMethod == "POST"
        })
        let corps = try #require(envoi.httpBody)
        let lignes = try #require(
            try JSONSerialization.jsonObject(with: corps) as? [[String: Any]]
        )
        let texte = try #require(lignes.first?["text"] as? String)
        #expect(JournalCipher.isSealed(texte))
        #expect(!texte.contains("Sam"))
        #expect(try Self.chiffre.open(texte) == "Course avec @Sam #PI")
        #expect((lignes.first?["tags_raw"] as? [String]) == [])
    }

    /// Sans la clé, l'amorçage n'envoie aucune note — surtout pas en clair.
    @Test func sansLaCleLAmorcageNEnvoieAucuneNote() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(JournalNote(dateKey: DateKey(raw: "2026-09-26")!, text: "Secret"))
        try context.save()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [(try Self.configBody(), 200)], thenAlways: Data(), status: 201
        )
        let engine = MirrorEngine(
            client: MirrorClient(store: try Self.store(avecCle: false), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.bootstrap()

        #expect(await transport.upsertedUUIDs(table: "journal_note").isEmpty)
        #expect(cursor.lastUUID(for: "journal_note") == nil)
    }
}
