import Foundation
import SwiftData
import Observation

/// Wires the app together in one place. Views receive it through the
/// environment and never build a client, engine or store themselves.
@MainActor
@Observable
final class AppEnvironment {
    let store: SecretStore
    let client: StravaClient
    let oauth: OAuthFlow
    let engine: SyncEngine
    let progress: SyncProgress
    /// The journal's folder, notes and watcher. Held here like every other
    /// long-lived piece of the app, so the window and the Settings scene get
    /// the same instance rather than two views of one folder.
    let journal = JournalStore()

    let mirrorClient: MirrorClient
    let mirror: MirrorEngine
    let mirrorProgress: MirrorProgress
    /// Kept alive for the life of the app, not just through `init`: its
    /// `start()` registers a `NotificationCenter` observer whose closure
    /// captures no `self`, so nothing else would keep this instance around —
    /// `deinit` would unsubscribe it the moment a purely-local variable went
    /// out of scope. See `MirrorRecorder`'s own doc comment.
    private let mirrorRecorder: MirrorRecorder
    /// Held so `forgetMirror()` can wipe it — see `MirrorBootstrapCursor.clear()`.
    /// `mirror` itself keeps its own copy internally; both wrap the same
    /// `UserDefaults.standard`, so clearing this one clears what `mirror`
    /// reads too.
    private let mirrorCursor: MirrorBootstrapCursor
    private var mirrorTask: Task<Void, Never>?

    var isAuthenticated: Bool
    var hasCredentials: Bool
    var athleteName: String?
    var errorMessage: String?
    var mirrorErrorMessage: String?

    private var runningTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    /// Installed by `RootView` so the menu bar can reach the window's own state.
    ///
    /// Nil until a window exists, which is exactly what disables the menu items:
    /// there is nothing to add an activity to before then.
    var requestNewActivity: (() -> Void)?
    var requestEditSelection: (() -> Void)?
    var requestDeleteSelection: (() -> Void)?
    var requestToggleFavorite: (() -> Void)?
    var requestImportGPX: (() -> Void)?
    var requestExportGPX: (() -> Void)?
    var requestExportJournalPDF: (() -> Void)?
    var requestToggleListStyle: (() -> Void)?

    /// `store`, `mirrorTransport` and `mirrorCursor` default to the real
    /// Keychain, `URLSession` and `UserDefaults.standard` — production never
    /// passes them explicitly, so `CairnApp.init`'s one call site keeps
    /// reading `AppEnvironment(container: container)` unchanged. The three
    /// parameters exist to be overridden, not used: `Tests/MirrorAutonomyTests.swift`
    /// (task 11) is the only caller that does, so a test can point the
    /// mirror at a throwaway store, a scripted transport and a throwaway
    /// `UserDefaults` suite instead of this Mac's real Keychain, real
    /// network and real preferences — without it, a test that merely
    /// constructed `AppEnvironment` would read whatever mirror project a
    /// developer's own machine happens to have configured, exactly the trap
    /// `MirrorEngine.init`'s own `cursor:` parameter documents at length.
    init(
        container: ModelContainer,
        store: SecretStore = KeychainStore(),
        mirrorTransport: MirrorTransport = URLSessionTransport(),
        mirrorCursor: MirrorBootstrapCursor = MirrorBootstrapCursor(defaults: .standard)
    ) {
        let progress = SyncProgress()
        let client = StravaClient(store: store)

        self.store = store
        self.client = client
        self.progress = progress
        self.oauth = OAuthFlow(store: store)
        self.engine = SyncEngine(
            source: client, container: container, progress: progress
        )
        self.isAuthenticated = store.tokens() != nil
        self.hasCredentials = store.credentials() != nil

        // Entirely local and synchronous: `MirrorClient.isConfigured` reads
        // the keychain, never the network, and `MirrorBootstrapCursor` only
        // wraps `UserDefaults`. Nothing below can delay or fail this `init` —
        // the foundational constraint the whole mirror plan holds to, and
        // `Tests/MirrorAutonomyTests.swift` (task 11) checks it directly.
        let mirrorClient = MirrorClient(store: store, transport: mirrorTransport)
        let mirrorProgress = MirrorProgress()
        let mirrorRecorder = MirrorRecorder(container: container)
        self.mirrorClient = mirrorClient
        self.mirrorProgress = mirrorProgress
        self.mirrorCursor = mirrorCursor
        self.mirror = MirrorEngine(
            client: mirrorClient, container: container, progress: mirrorProgress,
            cursor: mirrorCursor
        )
        self.mirrorRecorder = mirrorRecorder

        // Only once the mirror is configured — never unconditionally — per
        // `MirrorRecorder`'s own "When to start it" doc comment: nothing
        // prunes the outbox until a push actually runs, so a recorder started
        // on a Mac that never configures Supabase would grow the store by one
        // row per write, forever, for a feature nobody uses.
        //
        // Called from *here*, inside `init`, and not later: `CairnApp.init`
        // builds this environment before `DemoData.populateIfNeeded` or
        // `StoreMaintenance.run` touch the store, specifically so the
        // recorder — when it is going to run at all — is already listening
        // before the very first write of the launch. Anything written to a
        // configured mirror's store before the recorder starts is invisible
        // to the outbox forever; nothing revisits it later.
        if store.mirrorCredentials() != nil {
            mirrorRecorder.start()
        }

        // `MirrorProgress` is session state, exactly like `SyncProgress`: a
        // fresh instance starts with `lastPushAt == nil` on every launch, so
        // without this a mirror that finished bootstrapping yesterday would
        // read as one that has never run. A local `UserDefaults` read, never
        // the network — safe to fire without making `init` wait on it, the
        // same reasoning `restoreLastSyncDate()` follows for Strava.
        Task { [mirror] in await mirror.restoreProgress() }
    }

    func refreshAuthenticationState() {
        isAuthenticated = store.tokens() != nil
        hasCredentials = store.credentials() != nil
    }

    func saveCredentials(clientID: String, clientSecret: String) {
        do {
            try store.save(
                StravaCredentials(
                    clientID: clientID.trimmingCharacters(in: .whitespaces),
                    clientSecret: clientSecret.trimmingCharacters(in: .whitespaces)
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = "Impossible d'enregistrer les identifiants : \(error.localizedDescription)"
        }
        refreshAuthenticationState()
    }

    func connect() async {
        do {
            let athlete = try await oauth.authorize()
            let name = [athlete?.firstname, athlete?.lastname]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            athleteName = name.isEmpty ? nil : name
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshAuthenticationState()
    }

    func disconnect() {
        try? store.clearTokens()
        athleteName = nil
        refreshAuthenticationState()
    }

    /// Full sync: summaries, gear, then every pending stream.
    func syncNow() {
        runSync { [engine] in try await engine.syncAll() }
    }

    /// The cheap pass only — a couple of requests whatever the history size.
    func syncSummariesOnly() {
        runSync { [engine] in
            try await engine.syncAthlete()
            try await engine.syncSummaries()
            // A small bite of the backlog on every launch, so it empties without
            // anyone having to think about it. Bounded so opening the app stays
            // a couple of dozen requests rather than an hour of downloading.
            try await engine.syncBackfill(limit: Self.backfillPerLaunch)
        }
    }

    /// Ten activities, twenty requests. Enough to finish a year's library in a
    /// few weeks of ordinary use without ever being felt.
    static let backfillPerLaunch = 10

    /// Re-reads every summary from Strava, picking up anything edited there
    /// after the fact. Streams are left as they are.
    func resyncEverything() {
        runSync { [engine] in try await engine.resyncEverything() }
    }

    /// Whether launching the app looks for new activities.
    ///
    /// Only the summary pass runs: a couple of requests whatever the size of the
    /// history, so opening the app is never a surprise dent in the API quota.
    /// Detailed tracks stay on demand, via ⌘R.
    var syncsOnLaunch: Bool {
        get { defaults.object(forKey: Self.syncOnLaunchKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.syncOnLaunchKey) }
    }

    private static let syncOnLaunchKey = "syncsOnLaunch"

    func syncOnLaunch() {
        restoreLastSyncDate()
        pushMirrorOnLaunch()
        guard syncsOnLaunch, isAuthenticated else { return }
        syncSummariesOnly()
    }

    /// Sends whatever the outbox has accumulated since the last successful
    /// push, once per launch.
    ///
    /// Nothing else calls `pushNow()` but the settings button, and a mirror
    /// nobody ever opens the settings for would keep a trail that only ever
    /// grows: `MirrorRecorder`'s own doc comment justifies its conditional
    /// start by "an enregistreur started at launch would grow the store by one
    /// row per write, indefinitely" — a bound only an actual push can hold,
    /// never the fact that a project happens to be configured.
    ///
    /// Before Strava's own launch sync and independent of it: the mirror has
    /// nothing to do with `syncsOnLaunch` or with being signed in to Strava.
    /// Gated on the mirror's own two conditions instead, exactly as the
    /// settings button is — `push()` on an unconfigured Mac would throw
    /// `.notConfigured` and leave « Échec : Aucun projet Supabase… » on a
    /// screen belonging to a feature its owner never asked for.
    private func pushMirrorOnLaunch() {
        guard isMirrorConfigured, isMirrorSignedIn else { return }
        pushNow()
    }

    /// Reads the last successful run back out of the store.
    ///
    /// `SyncProgress` is session state: the engine only sets `lastRunAt` when a
    /// run finishes, so without this the app claimed it had never synced after
    /// every launch. Unconditional — the date is worth showing whether or not
    /// this launch goes on to sync, and whether or not anyone is signed in.
    func restoreLastSyncDate() {
        Task {
            guard let snapshot = try? await engine.stateSnapshot() else { return }
            // Set whatever the date turns out to be: a backlog is worth showing
            // on an app that has not synced this launch.
            progress.pendingStreams = snapshot.pendingStreamIDs.count
            progress.pendingBackfill = (try? await engine.backfillRemaining()) ?? 0
            guard let date = snapshot.lastRunAt else { return }
            // Only while still empty: the launch sync starts immediately after
            // this and may well finish first, and an awaited read must not put
            // the older date back over it.
            guard progress.lastRunAt == nil else { return }
            progress.lastRunAt = date
        }
    }

    /// Runs one sync operation with the guarantees every entry point needs:
    /// no overlapping runs (two concurrent syncs would double-spend the API
    /// quota), the error surfaced to the UI, and the slot released only by the
    /// task that owns it — see `cancelSync` for why.
    private func runSync(_ operation: @escaping @Sendable () async throws -> Void) {
        guard runningTask == nil, isAuthenticated else { return }
        let task = Task {
            do {
                try await operation()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        runningTask = task
        Task {
            _ = await task.value
            if runningTask == task { runningTask = nil }
        }
    }

    /// Cancellation is cooperative, so the slot can only be released by the
    /// task itself once it has actually unwound — clearing it here would let
    /// a second sync start alongside the dying one.
    func cancelSync() {
        guard let task = runningTask else { return }
        task.cancel()
        Task { _ = await task.value }
    }

    func loadDetail(stravaID: Int64) {
        Task { [engine] in
            try? await engine.fetchDetailIfNeeded(stravaID: stravaID)
            // Separately, and after: a failure to fetch the detail must not cost
            // the charts, and neither is worth surfacing as an error — the pane
            // says what is missing on its own.
            try? await engine.fetchStreamsIfNeeded(stravaID: stravaID)
        }
    }

    // MARK: - Mirror

    /// Whether a Supabase project is on file — decided purely from the
    /// keychain, never the network. Gates the settings screen's sign-in and
    /// bootstrap controls, and is what `Tests/MirrorAutonomyTests.swift`
    /// (task 11) checks stays `false`, never throws, when nothing is
    /// configured.
    var isMirrorConfigured: Bool { store.mirrorCredentials() != nil }

    /// Whether a usable, unexpired session is on file — `MirrorClient.isSignedIn`'s
    /// synchronous counterpart, read the same way `isMirrorConfigured` is:
    /// straight from the keychain, so a settings screen can gate its
    /// "amorcer" and "pousser" buttons without an `await`.
    var isMirrorSignedIn: Bool {
        guard let session = store.mirrorSession() else { return false }
        return !session.isExpired
    }

    /// Records the project the mirror writes to — the settings screen's
    /// « Enregistrer les identifiants » button.
    ///
    /// Changing the URL wipes the bootstrap cursor and the session, exactly as
    /// `forgetMirror()` does, and for the same reason its own doc comment
    /// gives: the cursor records progress against *one* project, and the field
    /// holding the URL is editable at all times. Without this, pointing the
    /// Mac at a second Supabase project — new URL, sign in again, « Lancer
    /// l'amorçage » — would silently skip every row whose `uuid` sorts before
    /// the old project's cursor, on a project that has never seen any of them.
    /// The session goes too: it was issued by the old project's GoTrue and
    /// means nothing to the new one.
    func saveMirrorCredentials(projectURL: String, anonKey: String) {
        let trimmedURL = projectURL.trimmingCharacters(in: .whitespaces)
        let trimmedKey = anonKey.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmedURL), !trimmedURL.isEmpty else {
            mirrorErrorMessage = "L'URL du projet est invalide."
            return
        }
        guard !trimmedKey.isEmpty else {
            mirrorErrorMessage = "La clé anon ne peut pas être vide."
            return
        }
        // Read before the save, or there is nothing left to compare against.
        // `nil` — no project on file yet — counts as different: a cursor
        // surviving a crash mid-`forgetMirror()` would otherwise still be
        // read against a project that has never received a row, and nobody
        // can hold a session for a project they have not configured.
        let previousURL = store.mirrorCredentials()?.projectURL
        do {
            try store.save(MirrorCredentials(projectURL: url, anonKey: trimmedKey))
            if previousURL != url {
                mirrorCursor.clear()
                try? store.clearMirrorSession()
                mirrorProgress.phase = .idle
                mirrorProgress.lastPushAt = nil
                mirrorProgress.failedUploads = 0
            }
            mirrorErrorMessage = nil
            // Configuring the project is exactly the moment `MirrorRecorder`
            // is meant to start — see its own "When to start it" doc comment,
            // and the identical guard in `init` above for a Mac that already
            // had credentials on launch. `start()` is a no-op if it is
            // already running, so this is safe to call again after an edit.
            mirrorRecorder.start()
        } catch {
            mirrorErrorMessage =
                "Impossible d'enregistrer les identifiants : \(error.localizedDescription)"
        }
    }

    func signInMirror(email: String, password: String) async {
        do {
            try await mirrorClient.signIn(email: email, password: password)
            mirrorErrorMessage = nil
        } catch {
            mirrorErrorMessage = error.localizedDescription
        }
    }

    /// Drops the project, the session, and every trace of them from the
    /// settings screen — the « Oublier ce miroir » button. Never touches a
    /// single local model: the mirror is a copy, and forgetting it must not
    /// cost the user any data.
    ///
    /// Clears `mirrorCursor` along with the keychain, not just the keychain:
    /// the outbox is left alone (its entries only ever name `table + uuid`,
    /// which stay correct against any project), but the bootstrap cursor
    /// records progress against *this* project specifically. Left in place,
    /// reconfiguring a *different* Supabase project afterward would silently
    /// skip every row sorting before the old cursor — see
    /// `MirrorBootstrapCursor.clear()`'s own doc comment.
    func forgetMirror() {
        cancelMirror()
        mirrorRecorder.stop()
        try? store.clearMirror()
        mirrorCursor.clear()
        mirrorProgress.phase = .idle
        mirrorProgress.lastPushAt = nil
        mirrorErrorMessage = nil
    }

    /// Uploads the whole library once, resuming wherever a previous attempt
    /// left off — the settings screen's « Lancer l'amorçage » button.
    func startBootstrap() {
        runMirror { [mirror] in try await mirror.bootstrap() }
    }

    /// Replays the outbox: everything changed locally since the last
    /// successful push.
    func pushNow() {
        runMirror { [mirror] in try await mirror.push() }
    }

    /// Runs one mirror operation with the same shape `runSync` gives Strava,
    /// and for the same reason: `MirrorEngine.bootstrap()` and `.push()` are
    /// actors, but they suspend at every request, so two calls left
    /// unguarded — an automatic push racing a hand-started bootstrap, say —
    /// would interleave freely instead of running one after the other.
    /// Harmless today (both are idempotent) but doubled traffic all the same,
    /// and worth ruling out here rather than trusting every future caller to
    /// remember it.
    ///
    /// Unlike `runSync`, nothing here sets `errorMessage`: `MirrorEngine`
    /// already records its own outcome straight into `mirrorProgress.phase`
    /// (`.failed(message)` on failure, back to `.idle` on a clean finish or a
    /// deliberate cancellation), which is the one place the settings screen
    /// already reads from. A second, separate error channel here would just
    /// be two sources of truth for the same fact.
    private func runMirror(_ operation: @escaping @Sendable () async throws -> Void) {
        guard mirrorTask == nil else { return }
        let task = Task {
            do { try await operation() } catch {}
        }
        mirrorTask = task
        Task {
            _ = await task.value
            if mirrorTask == task { mirrorTask = nil }
        }
    }

    /// Cancellation is cooperative, exactly as `cancelSync` explains: the slot
    /// can only be released by the task itself once it has actually unwound,
    /// so clearing it here would let a second bootstrap or push start
    /// alongside the one still dying.
    func cancelMirror() {
        guard let task = mirrorTask else { return }
        task.cancel()
        Task { _ = await task.value }
    }
}
