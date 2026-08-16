import Testing
import Foundation
import SwiftData
@testable import Cairn

/// Parks its first `send` until released, exactly like the transport
/// `Tests/MirrorBootstrapTests.swift` defines for the same reason —
/// catching a bootstrap or a push "genuinely in flight" rather than racing
/// it. Kept local to this file, on the same convention every other
/// mirror-test transport variant already follows.
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

/// The founding constraint of the whole mirror plan, made executable: the Mac
/// never depends on Supabase, at launch or afterward. The two tests in the
/// first suite are the plan's own wording turned into assertions; the second
/// suite locks five wiring guarantees task 10 put in place but that nothing
/// exercised — each one a way the launch path could silently start depending
/// on the network without a single test noticing.
@Suite("Autonomie face au miroir")
@MainActor
struct MirrorAutonomyTests {
    /// Le Mac ne dépend jamais de Supabase. Ce test est la forme exécutable de
    /// la contrainte fondatrice : construire l'environnement complet avec un
    /// miroir injoignable doit être sans effet observable.
    @Test func lApplicationSeConstruitAvecUnMiroirInjoignable() throws {
        let container = try AppModelContainer.inMemory()
        let environment = AppEnvironment(container: container)

        #expect(!environment.isMirrorConfigured)
        #expect(environment.errorMessage == nil)
    }

    /// Écrire, lire et chercher n'attendent rien du réseau. Un `save()` qui
    /// bloquerait sur un push serait une régression invisible en test unitaire
    /// mais fatale à l'usage.
    @Test func lesEcrituresLocalesNAttendentRien() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        let started = Date()
        for index in 0..<100 {
            context.insert(
                Activity(stravaID: Int64(index), name: "S\(index)", sportType: .run)
            )
        }
        try context.save()

        #expect(Date().timeIntervalSince(started) < 2)
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 100)
    }

    /// Le miroir peut être **configuré** — pas seulement absent — sans que la
    /// construction en pâtisse : c'est la forme littérale de « une URL
    /// Supabase pointée dans le vide » citée dans la contrainte fondatrice,
    /// plutôt que le cas, plus faible, où rien n'est configuré du tout.
    /// `transport` ne répond jamais réellement à un vrai serveur — un
    /// `StubTransport` scripté, jamais `URLSessionTransport` — donc si
    /// `AppEnvironment.init` en venait à l'attendre, ce test resterait bloqué
    /// plutôt que de simplement ralentir : la preuve la plus dure qu'aucune
    /// requête ne part pendant `init` est qu'aucune n'est même **possible**.
    @Test func lInitDuMiroirNeContacteJamaisLeReseau() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = StubTransport(alwaysRespondingWith: 200)

        let started = Date()
        let environment = AppEnvironment(
            container: container, store: try configuredStore(),
            mirrorTransport: transport, mirrorCursor: cursor
        )

        #expect(Date().timeIntervalSince(started) < 1)
        #expect(environment.isMirrorConfigured)
        #expect(environment.errorMessage == nil)
        #expect(await transport.requests().isEmpty)
    }
}

/// Cinq garanties de branchement que la tâche 10 a posées et qu'aucun test ne
/// couvrait : jusqu'ici, seule une lecture du code — les commentaires
/// d'`AppEnvironment.swift` et de `MirrorRecorder.swift` — les affirmait.
@Suite("Garanties de branchement du miroir")
@MainActor
struct MirrorWiringTests {
    /// Constructing `AppEnvironment` with a mirror already configured must
    /// leave `MirrorRecorder` already listening by the time `init` returns —
    /// the property that makes `CairnApp.init`'s own ordering (build the
    /// environment, *then* run `DemoData.populateIfNeeded` and
    /// `StoreMaintenance.run`) safe. `CairnApp` itself is a SwiftUI `App`
    /// entry point tied to a real container and a real window scene, not a
    /// practical target for a unit test — so what is exercised here is the
    /// guarantee `CairnApp`'s comment actually depends on: whatever write
    /// happens right after `AppEnvironment(container:)` returns is already
    /// inside the trail. A regression that moved `mirrorRecorder.start()`
    /// after the two writes in `CairnApp.init` — the exact failure this
    /// guards against — would leave this write unrecorded too.
    @Test func lEnregistreurEcouteDejaQuandLInitRend() throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        // Retained in a `let`, deliberately: `AppEnvironment` is a class, and
        // discarding it with `_ =` would drop the last strong reference to
        // its `MirrorRecorder` right there — `deinit` unsubscribes the
        // observer (see its own doc comment) before the write below ever
        // happens, which would fail this test for a reason that has nothing
        // to do with the guarantee under test.
        let environment = AppEnvironment(
            container: container, store: try configuredStore(),
            mirrorTransport: StubTransport(alwaysRespondingWith: 200), mirrorCursor: cursor
        )
        #expect(environment.isMirrorConfigured)

        // Simule la toute première écriture d'un lancement — celle que
        // `DemoData.populateIfNeeded` ou `StoreMaintenance.run` ferait,
        // *après* que `CairnApp.init` a fini de construire l'environnement.
        let context = ModelContext(container)
        context.insert(Athlete(stravaID: 1))
        try context.save()

        let entries = try ModelContext(container).fetch(FetchDescriptor<MirrorOutbox>())
        #expect(entries.contains { $0.table == "athlete" })
    }

    /// The other half of the same guard: nothing starts the recorder when no
    /// mirror is configured. Without this, the outbox would grow by one row
    /// per write, forever, on every Mac that has never touched Supabase —
    /// `MirrorRecorder`'s own "When to start it" doc comment names this
    /// exact cost.
    @Test func lEnregistreurResteMuetSansMiroirConfigure() throws {
        let container = try AppModelContainer.inMemory()
        // Retained, not discarded — see `lEnregistreurEcouteDejaQuandLInitRend`'s
        // doc comment: a discarded `AppEnvironment` deallocates its
        // `MirrorRecorder` immediately, which would leave the outbox empty
        // regardless of whether `init` ever started it, masking exactly the
        // regression this test exists to catch.
        let environment = AppEnvironment(container: container, store: InMemorySecretStore())
        #expect(!environment.isMirrorConfigured)

        let context = ModelContext(container)
        context.insert(Athlete(stravaID: 1))
        try context.save()

        let entries = try ModelContext(container).fetch(FetchDescriptor<MirrorOutbox>())
        #expect(entries.isEmpty)
    }

    /// `restoreProgress()` runs from a detached `Task` started inside `init`
    /// — never awaited by it, on purpose, since awaiting it would make
    /// `init` wait on I/O. That means this test cannot observe the read
    /// synchronously either; it polls, bounded exactly like
    /// `PausingTransport.waitForFirstRequest()` above, so a regression that
    /// dropped the call fails outright instead of hanging the suite.
    @Test func laDateDeDernierePousseeEstRelueAuLancement() async throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let pushedAt = Date(timeIntervalSince1970: 1_800_000_000)
        cursor.setLastPushAt(pushedAt)

        let environment = AppEnvironment(
            container: container, store: try configuredStore(),
            mirrorTransport: StubTransport(alwaysRespondingWith: 200), mirrorCursor: cursor
        )

        for _ in 0..<2000 where environment.mirrorProgress.lastPushAt == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(environment.mirrorProgress.lastPushAt == pushedAt)
    }

    /// Configuring the mirror mid-session — the settings screen's "save"
    /// button — starts the recorder immediately, and forgetting it stops
    /// the recorder immediately: both take effect synchronously, no launch
    /// or relaunch required.
    @Test func configurerLeMiroirDemarreLEnregistreurEtLoublierLarrete() throws {
        let container = try AppModelContainer.inMemory()
        let environment = AppEnvironment(container: container, store: InMemorySecretStore())
        #expect(!environment.isMirrorConfigured)

        environment.saveMirrorCredentials(projectURL: "https://x.supabase.co", anonKey: "anon")
        #expect(environment.isMirrorConfigured)

        let context = ModelContext(container)
        context.insert(Athlete(stravaID: 1))
        try context.save()
        let afterConfigure = try ModelContext(container).fetch(FetchDescriptor<MirrorOutbox>())
        #expect(afterConfigure.contains { $0.table == "athlete" })

        environment.forgetMirror()
        #expect(!environment.isMirrorConfigured)

        // Purges what the write above left, so the next check is unambiguous
        // about what happened *after* `forgetMirror()`.
        let cleanup = ModelContext(container)
        for entry in try cleanup.fetch(FetchDescriptor<MirrorOutbox>()) { cleanup.delete(entry) }
        try cleanup.save()

        context.insert(Athlete(stravaID: 2))
        try context.save()
        let afterForget = try ModelContext(container).fetch(FetchDescriptor<MirrorOutbox>())
        #expect(afterForget.isEmpty)
    }

    /// Two concurrent calls to `startBootstrap()` must not interleave: the
    /// second, made while the first is genuinely in flight (not merely
    /// racing it — `PausingTransport.waitForFirstRequest()` waits for the
    /// request to actually be sent), is a no-op. Proven by request count
    /// rather than by inspecting private state: if the guard ever failed,
    /// releasing the transport would let a second "athlete" upsert through
    /// once the first finished, and the final count would read 2, not 1.
    @Test func deuxAmorcagesConcurrentsNeSentrelacentPas() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(Athlete(stravaID: 1))
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = PausingTransport()
        let environment = AppEnvironment(
            container: container, store: try configuredStore(),
            mirrorTransport: transport, mirrorCursor: cursor
        )

        environment.startBootstrap()
        await transport.waitForFirstRequest()
        // Le créneau est déjà occupé : cet appel doit être un no-op immédiat.
        environment.startBootstrap()
        #expect(await transport.requests().count == 1)

        await transport.release()
        for _ in 0..<2000 where environment.mirrorProgress.lastPushAt == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(await transport.requests().count == 1)
    }

    /// The same slot serializes the *other* entry point too: `pushNow()`
    /// called while a `startBootstrap()` is still running must not start a
    /// second, overlapping operation — the pattern `runMirror` shares with
    /// `AppEnvironment.runSync(_:)`, guarding both callers with one flag
    /// rather than one each.
    @Test func pushNowPendantUnAmorcageEnCoursNeDemarreRien() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(Athlete(stravaID: 1))
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let transport = PausingTransport()
        let environment = AppEnvironment(
            container: container, store: try configuredStore(),
            mirrorTransport: transport, mirrorCursor: cursor
        )

        environment.startBootstrap()
        await transport.waitForFirstRequest()
        environment.pushNow()
        #expect(await transport.requests().count == 1)

        await transport.release()
        for _ in 0..<2000 where environment.mirrorProgress.lastPushAt == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(await transport.requests().count == 1)
    }
}
