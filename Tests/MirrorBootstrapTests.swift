import Testing
import Foundation
import SwiftData
@testable import Cairn

/// A transport that succeeds a fixed number of times, then fails every call
/// after that — a network dropped mid-bootstrap, not before it and not after
/// it. Kept local to this file rather than added to `Tests/MirrorTestSupport.swift`:
/// tasks 7, 9 and 11 depend on that file to the character, and this shape —
/// "fails partway through" — belongs to bootstrap resumption alone.
private actor FlakyTransport: MirrorTransport {
    private var remaining: Int
    private var sent: [URLRequest] = []

    init(succeeding: Int) {
        remaining = succeeding
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        guard remaining > 0 else {
            throw MirrorError.transport("coupure simulée")
        }
        remaining -= 1
        let response = HTTPURLResponse(
            url: URL(string: "https://x.supabase.co")!,
            statusCode: 201, httpVersion: nil, headerFields: nil
        )!
        return (Data(), response)
    }

    func requests() -> [URLRequest] { sent }
}

/// Parks its very first `send` until the test explicitly releases it, so a
/// cancellation can be timed at "a request is genuinely in flight" rather
/// than racing the engine to see whether anything ran at all before
/// `task.cancel()` lands. Kept local to this file for the same reason
/// `FlakyTransport` is.
private actor PausingTransport: MirrorTransport {
    private var sent: [URLRequest] = []
    private var gate: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        if sent.count == 1 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate = continuation
            }
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://x.supabase.co")!,
            statusCode: 201, httpVersion: nil, headerFields: nil
        )!
        return (Data(), response)
    }

    /// Lets the parked first `send` return its (successful) response.
    func release() {
        gate?.resume()
        gate = nil
    }

    /// Blocks until `send` has been called at least once — bounded, so a
    /// genuine regression fails the test instead of hanging the suite.
    func waitForFirstRequest() async {
        for _ in 0..<2000 where sent.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func requests() -> [URLRequest] { sent }
}

/// Runs a side effect right after its first `send` — the hook a test uses to
/// mutate the very container `MirrorEngine` is reading from, mid-bootstrap,
/// the way a concurrent delete would. Kept local to this file for the same
/// reason `FlakyTransport` is.
private actor DeletingTransport: MirrorTransport {
    private var sent: [URLRequest] = []
    private let onFirstRequest: @Sendable () throws -> Void

    init(onFirstRequest: @escaping @Sendable () throws -> Void) {
        self.onFirstRequest = onFirstRequest
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        if sent.count == 1 {
            try onFirstRequest()
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://x.supabase.co")!,
            statusCode: 201, httpVersion: nil, headerFields: nil
        )!
        return (Data(), response)
    }

    func requests() -> [URLRequest] { sent }
}

/// Every `uuid` sent to `table`, parsed the same way
/// `StubTransport.upsertedUUIDs(table:)` does — duplicated here rather than
/// imported, since that method lives on `StubTransport` specifically and the
/// transports above are not it.
private func extractedUUIDs(from requests: [URLRequest], table: String) -> [String] {
    requests.compactMap { request -> [String]? in
        guard request.url?.path == "/rest/v1/\(table)",
              let body = request.httpBody,
              let rows = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
        else { return nil }
        return rows.compactMap { $0["uuid"] as? String }
    }.flatMap { $0 }
}

// `MirrorProgress` is `@MainActor` (task 6's own interface), so every test
// that constructs one needs to run there too — `Tests/SyncEngineTests.swift`
// annotates its suites the same way for `SyncProgress`.
@Suite("Amorçage du miroir")
@MainActor
struct MirrorBootstrapTests {
    /// Un amorçage interrompu reprend là où il s'est arrêté, et un amorçage
    /// rejoué en entier ne casse rien. C'est la même propriété — l'idempotence —
    /// vue sous deux angles, et c'est le cœur de ce que 290 Mo sur une
    /// connexion domestique exigent.
    @Test func unAmorcageRejoueNEcritPasDeDoublon() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        for index in 0..<5 {
            context.insert(
                Activity(stravaID: Int64(index), name: "S\(index)", sportType: .run)
            )
        }
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.bootstrap()
        try await engine.bootstrap()

        let uuids = await transport.upsertedUUIDs(table: "activity")
        #expect(Set(uuids).count == 5)
        // Not just "no duplicate uuid appeared" — per
        // `Tests/MirrorTestSupport.swift`'s own warning, a `Set` count can
        // pass for the wrong reason. The cursor from the first pass must have
        // made the second pass send nothing at all for this table: exactly
        // one request, not two.
        let order = await transport.tableOrder()
        #expect(order.filter { $0 == "activity" }.count == 1)
    }

    /// L'amorçage emporte `edited_at` pour toute activité, éditée ou non — à
    /// `null` pour celles qui ne l'ont jamais été, jamais en l'omettant : un
    /// lot mélangeant les deux doit garder des clés uniformes, ce que
    /// PostgREST exige de tout tableau d'objets envoyé en un seul POST. Sans
    /// la colonne posée pour les lignes éditées, la future application web ne
    /// pourrait afficher « modifié le… » sur aucune des 852 lignes déjà en
    /// place, et rattraper après coup coûterait de toutes les réécrire. C'est
    /// le moteur qui le pose, jamais `mirrorRow` : la règle des quatre
    /// colonnes réservées reste gardée par `Tests/MirrorRowSchemaTests.swift`.
    @Test func lAmorcageEmporteLaDateDeDerniereEdition() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let edited = Activity(stravaID: 1, name: "Retouchée", sportType: .run)
        let editedAt = Date(timeIntervalSince1970: 1_700_000_000)
        edited.editedAt = editedAt
        let untouched = Activity(stravaID: 2, name: "Jamais retouchée", sportType: .run)
        context.insert(edited)
        context.insert(untouched)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )

        try await engine.bootstrap()

        let requests = await transport.requests()
        let rows = requests.filter { $0.url?.path == "/rest/v1/activity" }
            .compactMap(\.httpBody)
            .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
            .flatMap { $0 }
        let byUUID = Dictionary(
            uniqueKeysWithValues: rows.compactMap { row -> (String, [String: Any])? in
                (row["uuid"] as? String).map { ($0, row) }
            }
        )
        #expect(
            byUUID[edited.uuid]?["edited_at"] as? String
                == MirrorClient.iso8601.string(from: editedAt)
        )
        // Une activité jamais éditée reçoit tout de même la colonne — à
        // `null`, jamais absente : PostgREST rejette un lot dont les objets
        // n'ont pas tous les mêmes clés, et les deux activités de ce test
        // partent dans le même POST.
        let untouchedRow = try #require(byUUID[untouched.uuid])
        #expect(untouchedRow.keys.contains("edited_at"))
        #expect(untouchedRow["edited_at"] is NSNull)

        // Les deux lignes du même lot portent exactement les mêmes clés.
        let editedRow = try #require(byUUID[edited.uuid])
        #expect(Set(editedRow.keys) == Set(untouchedRow.keys))
    }

    /// Les parents partent avant les enfants — par confort de lecture, pas par
    /// contrainte : le schéma ne porte aucune clé étrangère entre tables du
    /// miroir (son propre commentaire d'en-tête le dit), donc un `lap` arrivé
    /// avant son activité serait accepté. Ce que l'ordre garantit, c'est qu'un
    /// amorçage interrompu à mi-chemin se lise, plutôt qu'il ne se lise pas.
    @Test func lesParentsPartentAvantLesEnfants() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let activity = Activity(stravaID: 1, name: "S", sportType: .run)
        context.insert(activity)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.bootstrap()

        let order = await transport.tableOrder()
        let activityIndex = order.firstIndex(of: "activity")
        let lapIndex = order.firstIndex(of: "lap")
        if let activityIndex, let lapIndex { #expect(activityIndex < lapIndex) }
        #expect(activityIndex != nil)
    }

    /// Une coupure entre deux tables laisse la première table confirmée
    /// intacte : reprendre l'amorçage ne la renvoie pas, et termine la
    /// seconde. Prouvé par un compte de requêtes, pas seulement par
    /// l'absence de doublon — la mise en garde du brief sur
    /// `upsertedUUIDs(table:)` qui répond `[]` en silence vaut aussi ici.
    @Test func unAmorcageInterrompuRepredOuIlSestArrete() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        for index in 0..<3 {
            let activity = Activity(stravaID: Int64(index), name: "S\(index)", sportType: .run)
            context.insert(activity)
            let lap = Lap(stravaID: Int64(index), lapIndex: 0)
            lap.activity = activity
            context.insert(lap)
        }
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let store = try configuredStore()

        // First attempt: the activity batch goes through, the lap batch does
        // not — a connection dropped after one table but before the next.
        let firstTransport = FlakyTransport(succeeding: 1)
        let firstEngine = MirrorEngine(
            client: MirrorClient(store: store, transport: firstTransport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        await #expect(throws: (any Error).self) {
            try await firstEngine.bootstrap()
        }
        // Two requests went out — the activity batch that succeeded, and the
        // lap batch whose response never came back — not just one: the
        // failure has to be attempted, not skipped, for the cursor logic
        // below to mean anything.
        let firstRequests = await firstTransport.requests()
        #expect(firstRequests.count == 2)
        #expect(firstRequests[0].url?.path == "/rest/v1/activity")
        #expect(firstRequests[1].url?.path == "/rest/v1/lap")

        // Second attempt, a fresh engine sharing the same cursor — the same
        // shape as relaunching the app. It must not resend the activities.
        let secondTransport = StubTransport(alwaysRespondingWith: 201)
        let secondEngine = MirrorEngine(
            client: MirrorClient(store: store, transport: secondTransport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await secondEngine.bootstrap()

        let secondOrder = await secondTransport.tableOrder()
        #expect(!secondOrder.contains("activity"))
        #expect(secondOrder.contains("lap"))
        let lapUUIDs = await secondTransport.upsertedUUIDs(table: "lap")
        #expect(Set(lapUUIDs).count == 3)
    }

    /// Une annulation n'est jamais un échec réseau : fermer la fenêtre de
    /// réglages pendant un amorçage doit laisser `MirrorProgress` silencieux
    /// sur l'incident, pas afficher une erreur — et cette annulation doit
    /// réellement couper un amorçage en train de tourner, pas juste devancer
    /// son tout premier `Task.checkCancellation()` avant qu'une requête ne
    /// soit partie.
    @Test func uneAnnulationEntreDeuxTablesNeMetPasEnEchec() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        // Une seule table peuplée suffit : `bootstrapOrder` en compte quinze
        // autres derrière "athlete", donc le `Task.checkCancellation()` qui
        // précède la suivante est garanti d'être atteint après elle.
        context.insert(Athlete(stravaID: 1))
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = PausingTransport()
        let progress = MirrorProgress()
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: progress, cursor: cursor
        )

        let task = Task { try await engine.bootstrap() }
        // Attend que la requête "athlete" soit réellement partie et bloquée
        // en attente de réponse, plutôt que d'annuler à l'aveugle.
        await transport.waitForFirstRequest()
        task.cancel()
        // Laisse cette première requête réussir malgré tout : c'est le
        // `Task.checkCancellation()` de la table suivante, pas une erreur
        // réseau au milieu de celle-ci, qui doit porter l'annulation.
        await transport.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        // La ligne "athlete" est bien partie avant que l'annulation ne
        // prenne effet — la preuve que ceci a exercé une vraie requête, pas
        // seulement le tout premier point de contrôle avant que rien n'ait
        // tourné.
        #expect(await transport.requests().count == 1)
        #expect(progress.phase == .idle)
    }

    /// La date de dernière synchro survit à un relancement de l'app :
    /// `MirrorProgress` est un état de session qui repart à `nil` à chaque
    /// lancement, donc sans lecture explicite du curseur persistant, un
    /// miroir entièrement amorcé hier se lirait comme un miroir qui n'a
    /// jamais tourné.
    @Test func laDateDeDerniereSynchroSurvitAUnRelancement() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(Athlete(stravaID: 1))
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.bootstrap()

        // Un second `MirrorEngine`, avec un second `MirrorProgress` neuf —
        // la forme exacte d'un nouveau lancement de l'app, où plus rien en
        // mémoire ne se souvient du premier amorçage.
        let freshProgress = MirrorProgress()
        #expect(freshProgress.lastPushAt == nil)
        let secondEngine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: freshProgress, cursor: cursor
        )
        await secondEngine.restoreProgress()

        #expect(freshProgress.lastPushAt != nil)
    }

    /// Une table de plus de 200 lignes tient sur deux lots. Une coupure entre
    /// les deux laisse le curseur au-delà de la première page — la reprise
    /// doit repartir exactement là, ni renvoyer la première page ni sauter la
    /// seconde. `batchSize` vaut 200 dans `MirrorEngine` ; aucun test avant
    /// celui-ci n'avait de table dépassant ce seuil, donc rien ne couvrait
    /// une vraie frontière de page.
    @Test func unAmorcageDePlusDeDeuxCentsLignesRepredALaBonnePage() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        var uuids: [String] = []
        for index in 0..<250 {
            let activity = Activity(stravaID: Int64(index), name: "S\(index)", sportType: .run)
            context.insert(activity)
            uuids.append(activity.uuid)
        }
        try context.save()
        let sortedUUIDs = uuids.sorted()
        // What a correct first page and a correct second page must contain —
        // computed independently of anything the engine does, so this stays
        // a check on its behaviour rather than a restatement of it.
        let expectedFirstPage = Set(sortedUUIDs.prefix(200))
        let expectedSecondPage = Set(sortedUUIDs.suffix(50))

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let store = try configuredStore()

        // First attempt: the first page (200 rows) succeeds, the second (the
        // remaining 50) does not — a connection dropped exactly at a page
        // boundary, not inside one.
        let firstTransport = FlakyTransport(succeeding: 1)
        let firstEngine = MirrorEngine(
            client: MirrorClient(store: store, transport: firstTransport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        await #expect(throws: (any Error).self) {
            try await firstEngine.bootstrap()
        }
        // Two requests attempted — the successful 200-row page and the
        // 50-row page whose response never came back. `FlakyTransport`
        // records a request whether or not it went on to fail, so reading
        // rows back out of *this* array would count the failed attempt's
        // rows too; `expectedFirstPage`, computed independently above, is
        // what actually matters.
        #expect(await firstTransport.requests().count == 2)

        // Second attempt, a fresh engine sharing the same cursor — the same
        // shape as relaunching the app. It must send exactly the remaining
        // 50, not the first 200 again and not fewer than 50.
        let secondTransport = StubTransport(alwaysRespondingWith: 201)
        let secondEngine = MirrorEngine(
            client: MirrorClient(store: store, transport: secondTransport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await secondEngine.bootstrap()

        let secondUUIDs = Set(await secondTransport.upsertedUUIDs(table: "activity"))
        #expect(secondUUIDs == expectedSecondPage)
        #expect(secondUUIDs.isDisjoint(with: expectedFirstPage))
    }

    /// Une suppression concurrente, mid-bootstrap, ne doit jamais coûter une
    /// ligne qui existe toujours. Reproduction directe du round 2 de revue :
    /// paginer par position (`fetchOffset`) plutôt que par clé (`uuid >
    /// curseur`) laissait une suppression derrière le curseur décaler tout
    /// ce qui suit d'un cran, sautant en silence la ligne désormais mal
    /// alignée avec la page suivante — une perte permanente, puisque le
    /// curseur ne revient jamais en arrière et que l'outbox de la tâche 8 ne
    /// voit que ce qui *change*, pas ce qu'un décalage a manqué.
    @Test func uneSuppressionConcurrentePendantLAmorcageNeSauteAucuneLigne() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        var uuids: [String] = []
        for index in 0..<300 {
            let activity = Activity(stravaID: Int64(index), name: "S\(index)", sportType: .run)
            context.insert(activity)
            uuids.append(activity.uuid)
        }
        try context.save()
        let sortedUUIDs = uuids.sorted()
        // Squarely inside the first page's 200 rows — deleting it once that
        // page has already been fetched (but not yet before) is exactly the
        // shape that shifted an offset-based page 2 by one row.
        let victimUUID = sortedUUIDs[50]
        let expectedSurvivors = Set(sortedUUIDs).subtracting([victimUUID])

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }

        let transport = DeletingTransport {
            let deleteContext = ModelContext(container)
            let victim = try deleteContext.fetch(
                FetchDescriptor<Activity>(predicate: #Predicate { $0.uuid == victimUUID })
            ).first
            if let victim { deleteContext.delete(victim) }
            try deleteContext.save()
        }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.bootstrap()

        let sentUUIDs = extractedUUIDs(from: await transport.requests(), table: "activity")
        let missing = expectedSurvivors.subtracting(sentUUIDs)
        #expect(missing.isEmpty, "ligne(s) sautée(s) : \(missing.sorted())")
        #expect(Set(sentUUIDs).count == sentUUIDs.count, "un uuid est parti deux fois")
        // The victim itself is *not* asserted absent: its row was already
        // fetched into page 1's batch, and serialized into that request's
        // body, before the delete this test triggers ever runs — deleting a
        // row after it is already in flight does not, and should not, un-send
        // it. What matters is every *other* row: none of them may be lost to
        // the shift the deletion causes for whichever page reads next.
    }
}
