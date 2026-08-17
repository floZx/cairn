import Testing
import Foundation
import SwiftData
@testable import Cairn

/// `MirrorProgress` is `@MainActor`, so every suite that builds one is too —
/// the same reasoning `MirrorPushTests` states.
@Suite("Lecture du miroir")
@MainActor
struct MirrorPullTests {
    /// Une page de `journal_note`, telle que PostgREST la rend.
    private static func page(
        uuid: String = "n1", dateKey: String = "2026-08-16", text: String = "Venu du web",
        updatedAt: String = "2026-08-16T10:00:00.123456+00:00",
        editedAt: String? = "2026-08-16T10:00:00.123456+00:00",
        deletedAt: String? = nil
    ) -> Data {
        var row: [String: Any] = [
            "uuid": uuid, "date_key_raw": dateKey, "text": text, "updated_at": updatedAt,
        ]
        row["edited_at"] = editedAt as Any? ?? NSNull()
        row["deleted_at"] = deletedAt as Any? ?? NSNull()
        return try! JSONSerialization.data(withJSONObject: [row])
    }

    private static func engine(
        _ container: ModelContainer, _ transport: StubTransport, _ cursor: MirrorBootstrapCursor
    ) throws -> MirrorEngine {
        MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
    }

    /// Le cas qui justifie tout le fichier : une note écrite depuis le
    /// navigateur arrive sur le Mac.
    @Test func uneNoteInconnueEstCreee() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        // Une seule page : la deuxième réponse est vide, ce qui clôt la boucle.
        let transport = StubTransport(responses: [(Self.page(), 200), (Data("[]".utf8), 200)])

        try await Self.engine(container, transport, cursor).pull()

        let notes = try ModelContext(container).fetch(FetchDescriptor<JournalNote>())
        #expect(notes.count == 1)
        #expect(notes.first?.uuid == "n1")
        #expect(notes.first?.text == "Venu du web")
        #expect(notes.first?.dateKeyRaw == "2026-08-16")
    }

    /// L'identité distante est reprise telle quelle. Une note qui recevrait un
    /// `uuid` neuf repartirait en seconde ligne, et la journée serait racontée
    /// deux fois.
    @Test func lIdentiteDistanteEstConservee() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [(Self.page(uuid: "venu-du-web"), 200), (Data("[]".utf8), 200)]
        )

        try await Self.engine(container, transport, cursor).pull()

        let notes = try ModelContext(container).fetch(FetchDescriptor<JournalNote>())
        #expect(notes.first?.uuid == "venu-du-web")
    }

    /// Les étiquettes sont recalculées ici, jamais reprises de la colonne : la
    /// règle du Mac est l'originale, celle du web un portage.
    @Test func lesEtiquettesSontRecalculees() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [(Self.page(text: "Sortie avec #Tom"), 200), (Data("[]".utf8), 200)]
        )

        try await Self.engine(container, transport, cursor).pull()

        let notes = try ModelContext(container).fetch(FetchDescriptor<JournalNote>())
        #expect(notes.first?.tagsRaw == ["Tom"])
    }

    /// La version distante gagne quand elle est plus récente.
    @Test func laVersionLaPlusRecenteGagne() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let locale = JournalNote(dateKey: DateKey(raw: "2026-08-16")!, text: "Écrit sur le Mac")
        locale.uuid = "n1"
        locale.applyMirrored(text: "Écrit sur le Mac", editedAt: Date(timeIntervalSince1970: 1000))
        context.insert(locale)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [
                (Self.page(text: "Corrigé depuis le téléphone",
                           editedAt: "2026-08-16T10:00:00.000+00:00"), 200),
                (Data("[]".utf8), 200),
            ]
        )

        try await Self.engine(container, transport, cursor).pull()

        let notes = try ModelContext(container).fetch(FetchDescriptor<JournalNote>())
        #expect(notes.count == 1)
        #expect(notes.first?.text == "Corrigé depuis le téléphone")
    }

    /// Et perd quand elle est plus ancienne — sans quoi ouvrir l'application
    /// écraserait ce qu'on vient d'écrire dessus.
    @Test func uneVersionDistantePlusAncienneNEcrasePas() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let locale = JournalNote(dateKey: DateKey(raw: "2026-08-16")!, text: "Écrit à l'instant")
        locale.uuid = "n1"
        context.insert(locale)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [
                (Self.page(text: "Vieille version",
                           editedAt: "2020-01-01T10:00:00.000+00:00"), 200),
                (Data("[]".utf8), 200),
            ]
        )

        try await Self.engine(container, transport, cursor).pull()

        let notes = try ModelContext(container).fetch(FetchDescriptor<JournalNote>())
        #expect(notes.first?.text == "Écrit à l'instant")
    }

    /// Une note vidée depuis le web disparaît du Mac.
    @Test func uneNoteEffaceeAilleursDisparait() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let locale = JournalNote(dateKey: DateKey(raw: "2026-08-16")!, text: "À supprimer")
        locale.uuid = "n1"
        locale.applyMirrored(text: "À supprimer", editedAt: Date(timeIntervalSince1970: 1000))
        context.insert(locale)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [
                (Self.page(editedAt: "2026-08-16T10:00:00.000+00:00",
                           deletedAt: "2026-08-16T10:00:00.000+00:00"), 200),
                (Data("[]".utf8), 200),
            ]
        )

        try await Self.engine(container, transport, cursor).pull()

        #expect(try ModelContext(container).fetch(FetchDescriptor<JournalNote>()).isEmpty)
    }

    /// Une ligne sans `edited_at` ne peut être arbitrée contre rien. Elle est
    /// laissée de côté plutôt que devinée — deviner, ici, c'est écraser.
    @Test func uneLigneSansHorlogeDAuteurEstIgnoree() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(
            responses: [(Self.page(editedAt: nil), 200), (Data("[]".utf8), 200)]
        )

        try await Self.engine(container, transport, cursor).pull()

        #expect(try ModelContext(container).fetch(FetchDescriptor<JournalNote>()).isEmpty)
    }

    /// Ce qui est relu ne repart pas. Sans l'exemption d'outbox, le Mac
    /// renverrait sous sa propre horloge ce qu'il vient de recevoir.
    @Test func uneNoteRelueNeRepartPas() async throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(responses: [(Self.page(), 200), (Data("[]".utf8), 200)])

        try await Self.engine(container, transport, cursor).pull()

        #expect(try ModelContext(container).fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }

    /// Le curseur avance, et la requête suivante le porte : sans cela chaque
    /// lancement relirait le journal entier.
    @Test func leCurseurAvanceEtEstRenvoye() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(responses: [(Self.page(), 200), (Data("[]".utf8), 200)])

        try await Self.engine(container, transport, cursor).pull()
        #expect(cursor.lastPulledAt(for: "journal_note") != nil)

        // Un second passage, avec un curseur déjà posé : la requête doit
        // porter un `updated_at=gte.…`.
        let second = StubTransport(responses: [(Data("[]".utf8), 200)])
        try await Self.engine(container, second, cursor).pull()
        let query = await second.requests().first?.url?.query ?? ""
        #expect(query.contains("updated_at=gte."))
    }

    /// Oublier le miroir efface aussi la position de lecture. Sans cela,
    /// reconfigurer un autre projet Supabase relirait à partir d'une date qui
    /// ne veut plus rien dire pour lui.
    @Test func oublierLeMiroirEffaceLaPositionDeLecture() {
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        cursor.setLastPulledAt(Date(), for: "journal_note")

        cursor.clear()

        #expect(cursor.lastPulledAt(for: "journal_note") == nil)
    }

    /// Les deux formes que Postgres renvoie, selon qu'il a des fractions de
    /// seconde ou non. Un seul formateur en refuserait une des deux, et la
    /// moitié des lignes seraient silencieusement ignorées.
    @Test func lesDeuxPrecisionsDeDateSontLues() {
        #expect(MirrorEngine.date(from: "2026-08-16T10:00:00+00:00") != nil)
        #expect(MirrorEngine.date(from: "2026-08-16T10:00:00.482913+00:00") != nil)
        #expect(MirrorEngine.date(from: "pas une date") == nil)
    }
}

/// Ce que `pushTable` sait envoyer, contre ce que le miroir prétend porter.
///
/// Écrit après coup : les deux tables du journal manquaient à ce `switch`
/// alors qu'elles figuraient dans `bootstrapOrder` depuis leur arrivée. Une
/// note modifiée sur le Mac tombait dans `default` — assertion en débogage,
/// et en production une entrée d'outbox ni envoyée ni consommée, qui revenait
/// à chaque poussée.
@Suite("Couverture de la poussée")
@MainActor
struct MirrorPushCoverageTests {
    /// Chaque table du miroir sait être poussée. L'attente est dérivée de
    /// `bootstrapOrder` — jamais d'une seconde liste écrite à la main, qui
    /// serait exactement la liste qu'on oublie de compléter.
    @Test func chaqueTableDuMiroirSaitEtrePoussee() async throws {
        for table in MirrorEngine.bootstrapOrder {
            let container = try AppModelContainer.inMemory()
            let context = ModelContext(container)
            // Une entrée d'outbox pour une ligne qui n'existe pas : ce que
            // `pushTable` en fait n'importe pas ici, seulement qu'il connaisse
            // la table. Une ligne introuvable est un cas que la poussée gère
            // déjà — elle la traite comme supprimée entre-temps.
            context.insert(
                MirrorOutbox(table: table, rowUUID: UUID().uuidString, isDeletion: false)
            )
            try context.save()

            let (cursor, suiteName) = freshCursor()
            defer { discard(suiteName) }
            let engine = MirrorEngine(
                client: MirrorClient(
                    store: try configuredStore(),
                    transport: StubTransport(alwaysRespondingWith: 201)
                ),
                container: container, progress: MirrorProgress(), cursor: cursor
            )

            try await engine.push()

            #expect(
                try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty,
                "\(table) laisse son entrée dans l'outbox — table absente de pushTable ?"
            )
        }
    }
}
