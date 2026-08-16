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

// `MirrorProgress` is `@MainActor` (task 6's own interface), so every test
// that constructs one needs to run there too — `Tests/SyncEngineTests.swift`
// annotates its suites the same way for `SyncProgress`.
@Suite("Amorçage du miroir")
@MainActor
struct MirrorBootstrapTests {
    /// A suite of its own per test, never `.standard` — that one belongs to
    /// whatever process is running the suite, exactly the trap
    /// `Tests/JournalStoreTests.swift` already avoids for `JournalStore`.
    /// Returns the suite name alongside the cursor so the caller can `defer`
    /// its cleanup, the other half of what that same file does
    /// (`removePersistentDomain(forName:)`) and what an earlier version of
    /// this file skipped.
    private func freshCursor() -> (cursor: MirrorBootstrapCursor, suiteName: String) {
        let suiteName = "cairn.tests.mirror.\(UUID().uuidString)"
        return (MirrorBootstrapCursor(defaults: UserDefaults(suiteName: suiteName)!), suiteName)
    }

    private func discard(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

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

    /// Les parents partent avant les enfants. Une ligne `lap` dont l'activité
    /// n'est pas encore là n'a rien à quoi se rattacher.
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
}
