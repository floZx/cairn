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
        // Une page, puis « [] » partout : rien d'autre n'a changé.
        let transport = StubTransport(responses: [(Self.page(), 200)], thenAlways: Data("[]".utf8))

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
            responses: [(Self.page(uuid: "venu-du-web"), 200)],
            thenAlways: Data("[]".utf8)
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
            responses: [(Self.page(text: "Sortie avec #Tom"), 200)],
            thenAlways: Data("[]".utf8)
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
            ], thenAlways: Data("[]".utf8)
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
            ], thenAlways: Data("[]".utf8)
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
            ], thenAlways: Data("[]".utf8)
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
            responses: [(Self.page(editedAt: nil), 200)],
            thenAlways: Data("[]".utf8)
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
        let transport = StubTransport(responses: [(Self.page(), 200)], thenAlways: Data("[]".utf8))

        try await Self.engine(container, transport, cursor).pull()

        #expect(try ModelContext(container).fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }

    /// Le curseur avance, et la requête suivante le porte : sans cela chaque
    /// lancement relirait le journal entier.
    @Test func leCurseurAvanceEtEstRenvoye() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(responses: [(Self.page(), 200)], thenAlways: Data("[]".utf8))

        try await Self.engine(container, transport, cursor).pull()
        #expect(cursor.lastPulledAt(for: "journal_note") != nil)

        // Un second passage, avec un curseur déjà posé : la requête doit
        // porter un `updated_at=gte.…`.
        let second = StubTransport(responses: [], thenAlways: Data("[]".utf8))
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

/// Les objectifs nutritionnels, qui ne passent pas par l'outbox.
@Suite("Objectifs nutritionnels")
@MainActor
struct MirrorNutritionTargetTests {
    /// Ils partent à chaque poussée, outbox vide comprise : rien n'écrit dans
    /// SwiftData quand on les change, donc rien ne les inscrirait jamais dans
    /// une outbox, et une poussée conditionnelle ne les enverrait donc jamais.
    @Test func lesObjectifsPartentMemeSansRienDAutre() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.push(
            nutritionTargets: .init(proteinG: 130, fatG: 66, weightGoalKg: 70)
        )

        let tables = await transport.tableOrder()
        #expect(tables == ["nutrition_target"])
    }

    /// La ligne porte l'identifiant de la personne comme clé : une seule ligne
    /// par compte, et pas de clé fixe qui se heurterait d'un compte à l'autre.
    @Test func laLigneEstIdentifieeParLaPersonne() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.push(
            nutritionTargets: .init(proteinG: 130, fatG: 66, weightGoalKg: 70)
        )

        // `configuredStore()` pose la session sur l'identifiant « u ».
        #expect(await transport.upsertedUUIDs(table: "nutrition_target") == ["u"])
    }

    /// Sans objectifs fournis, rien ne part — une poussée qui n'a rien d'autre
    /// à faire ne doit pas inventer une requête.
    @Test func sansObjectifsRienNePart() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.push()

        #expect(await transport.requests().isEmpty)
    }
}

/// La lecture des trois tables de repas.
///
/// Elles n'ont pas d'horloge d'auteur, à la différence de `JournalNote` :
/// l'arbitrage passe par l'outbox, et c'est ce que ces tests surveillent
/// avant tout.
@Suite("Lecture des repas")
@MainActor
struct MirrorPullNutritionTests {
    private static func page(_ rows: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: rows)
    }

    private static func aliment(
        uuid: String = "f1", grams: Double = 100, nom: String = "Pomme",
        slot: String? = nil, deletedAt: String? = nil
    ) -> [String: Any] {
        [
            "uuid": uuid, "date_key_raw": "2026-08-16",
            "meal_slot_uuid": slot as Any? ?? NSNull(),
            "product_code": NSNull(), "food_name": nom,
            "kcal100": 52.0, "protein100": 0.3, "carbs100": 14.0, "fat100": 0.2,
            "grams": grams, "sort_order": 0,
            "updated_at": "2026-08-16T10:00:00.000+00:00",
            "deleted_at": deletedAt as Any? ?? NSNull(),
        ]
    }

    private static func engine(
        _ container: ModelContainer, _ transport: StubTransport, _ cursor: MirrorBootstrapCursor
    ) throws -> MirrorEngine {
        MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
    }

    /// Six tables sont relues, et `journal_note` reste la première.
    ///
    /// Dérivée d'aucune autre liste, celle-ci : elle dit exactement ce que le
    /// navigateur sait écrire, et le jour où il apprend à écrire autre chose
    /// c'est ce test qu'il faut voir échouer.
    @Test func lOrdreDeLectureCouvreCeQueLeWebEcrit() {
        #expect(
            MirrorEngine.pullOrder == [
                "journal_note", "nutrition_day", "food_entry", "meal_note",
                "weight_entry",
                // En dernier : ses octets se téléchargent un par un.
                "journal_attachment",
            ]
        )
    }

    /// Un aliment saisi sur le téléphone arrive sur le Mac, rattaché à son
    /// créneau.
    @Test func unAlimentInconnuEstCree() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 40)
        context.insert(slot)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        // Trois tables avant `food_entry` dans l'ordre de lecture, chacune une
        // page vide, puis l'aliment, puis les pages de clôture.
        let vide = Data("[]".utf8)
        // `journal_note` et `nutrition_day` d'abord, vides ; puis l'aliment ;
        // le repli couvre la clôture de `food_entry` et `meal_note`.
        let transport = StubTransport(
            responses: [
                (vide, 200), (vide, 200),
                (Self.page([Self.aliment(slot: slot.uuid)]), 200),
            ],
            thenAlways: vide
        )

        try await Self.engine(container, transport, cursor).pull()

        let entries = try ModelContext(container).fetch(FetchDescriptor<FoodEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.uuid == "f1")
        #expect(entries.first?.foodName == "Pomme")
        #expect(entries.first?.grams == 100)
        #expect(entries.first?.mealSlot?.uuid == slot.uuid)
    }

    /// Une ligne que l'outbox retient n'est pas écrasée : c'est tout
    /// l'arbitrage de ces trois tables, faute d'horloge d'auteur.
    @Test func uneLigneEnAttenteDEnvoiNEstPasEcrasee() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = FoodEntry(
            dateKey: DateKey(raw: "2026-08-16")!, mealSlot: nil, foodName: "Écrit ici",
            kcal100: 1, protein100: 1, carbs100: 1, fat100: 1, grams: 250
        )
        entry.uuid = "f1"
        context.insert(entry)
        context.insert(MirrorOutbox(table: "food_entry", rowUUID: "f1", isDeletion: false))
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let vide = Data("[]".utf8)
        let transport = StubTransport(
            responses: [(vide, 200), (vide, 200), (Self.page([Self.aliment(grams: 999, nom: "Venu du serveur")]), 200)],
            thenAlways: vide
        )

        try await Self.engine(container, transport, cursor).pull()

        let entries = try ModelContext(container).fetch(FetchDescriptor<FoodEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.foodName == "Écrit ici")
        #expect(entries.first?.grams == 250)
    }

    /// Le curseur avance quand même sur une ligne protégée : la retenir ferait
    /// relire la même page à chaque lancement.
    @Test func leCurseurAvanceMemeSurUneLigneProtegee() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(MirrorOutbox(table: "food_entry", rowUUID: "f1", isDeletion: false))
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let vide = Data("[]".utf8)
        let transport = StubTransport(
            responses: [(vide, 200), (vide, 200), (Self.page([Self.aliment()]), 200)],
            thenAlways: vide
        )

        try await Self.engine(container, transport, cursor).pull()

        #expect(cursor.lastPulledAt(for: "food_entry") != nil)
    }

    /// Un aliment supprimé sur le téléphone disparaît du Mac.
    @Test func unAlimentEffaceAilleursDisparait() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = FoodEntry(
            dateKey: DateKey(raw: "2026-08-16")!, mealSlot: nil, foodName: "Pomme",
            kcal100: 52, protein100: 0.3, carbs100: 14, fat100: 0.2, grams: 100
        )
        entry.uuid = "f1"
        context.insert(entry)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let vide = Data("[]".utf8)
        let transport = StubTransport(
            responses: [(vide, 200), (vide, 200), (Self.page([Self.aliment(deletedAt: "2026-08-16T11:00:00.000+00:00")]), 200)],
            thenAlways: vide
        )

        try await Self.engine(container, transport, cursor).pull()

        #expect(try ModelContext(container).fetch(FetchDescriptor<FoodEntry>()).isEmpty)
    }

    /// Ce qui est relu ne repart pas — la même exemption que pour le journal.
    @Test func unAlimentReluNeRepartPas() async throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let vide = Data("[]".utf8)
        let transport = StubTransport(
            responses: [(vide, 200), (vide, 200), (Self.page([Self.aliment()]), 200)],
            thenAlways: vide
        )

        try await Self.engine(container, transport, cursor).pull()

        #expect(try ModelContext(container).fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }
}

/// La pagination à travers les horodatages identiques.
///
/// Écrite après coup, sur un blocage constaté : `food_entry` figé à 09:12
/// pendant des heures. `now()` en Postgres est l'heure de la **transaction**,
/// donc les deux cents lignes d'un même lot d'envoi portent toutes le même
/// `updated_at` — une page entière peut ne contenir qu'un seul horodatage, et
/// la boucle qui s'arrêtait là laissait la table figée pour toujours.
@Suite("Pagination de la lecture")
@MainActor
struct MirrorPullPaginationTests {
    /// Une page pleine de notes partageant toutes le même `updated_at`.
    private static func pageIdentique(_ debut: Int, _ nombre: Int, horodatage: String) -> Data {
        let rows = (debut..<(debut + nombre)).map { i -> [String: Any] in
            [
                "uuid": "n\(i)", "date_key_raw": "2026-08-16", "text": "Note \(i)",
                "updated_at": horodatage, "edited_at": horodatage,
                "deleted_at": NSNull(),
            ]
        }
        return try! JSONSerialization.data(withJSONObject: rows)
    }

    /// Cent lignes au même horodatage, puis cent autres, puis une page courte :
    /// les deux cent dix doivent arriver.
    @Test func unGroupeDHorodatagesIdentiquesNeBloquePas() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let meme = "2026-08-16T09:12:00.000+00:00"
        // `journal_note` est la première table lue : le script la vise, le
        // repli couvre les trois suivantes.
        let scripte = StubTransport(
            responses: [
                (Self.pageIdentique(0, 100, horodatage: meme), 200),
                (Self.pageIdentique(100, 100, horodatage: meme), 200),
                (Self.pageIdentique(200, 10, horodatage: meme), 200),
            ],
            thenAlways: Data("[]".utf8)
        )
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: scripte),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.pull()

        let notes = try ModelContext(container).fetch(FetchDescriptor<JournalNote>())
        #expect(notes.count == 210)
    }

    /// Et le décalage est bien celui qu'on croit : 0, puis 100, puis 200.
    @Test func leDecalageAvanceDUnePageALaFois() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let meme = "2026-08-16T09:12:00.000+00:00"
        let transport = StubTransport(
            responses: [
                (Self.pageIdentique(0, 100, horodatage: meme), 200),
                (Self.pageIdentique(100, 100, horodatage: meme), 200),
                (Self.pageIdentique(200, 10, horodatage: meme), 200),
            ],
            thenAlways: Data("[]".utf8)
        )
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.pull()

        let decalages = await transport.requests()
            .filter { $0.url?.path == "/rest/v1/journal_note" }
            .map { requete -> String in
                URLComponents(url: requete.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "offset" }?.value ?? "0"
            }
        #expect(decalages == ["0", "100", "200"])
    }
}
