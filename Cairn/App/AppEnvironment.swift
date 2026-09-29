import AppKit
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
    /// The journal's notes and what is being typed into one. Held here like
    /// every other long-lived piece of the app, so the window and the Settings
    /// scene get the same instance rather than two views of one journal.
    let journal: JournalStore

    /// Le verrou du journal, une fois par ouverture de l'application. Tenu ici
    /// pour cette raison même : un `@State` de vue redemanderait à chaque
    /// reconstruction.
    let journalLock = JournalLock()
    /// The observers that close the journal on their own — kept so they live
    /// as long as the app. See `watchForJournalLock()`.
    var lockObservers: [NSObjectProtocol] = []

    /// Ce que la bibliothèque dit des journées, calculé une fois par écriture
    /// et non une fois par rendu. Tenu ici parce qu'il doit survivre aux
    /// reconstructions de `RootView` : un `@State` le referait à chaque
    /// création de la structure, et reposerait son observateur avec.
    let journalLibrary = JournalLibraryCache()

    let mirrorClient: MirrorClient
    let mirror: MirrorEngine
    /// Garmin Connect, written to and never read into the journal: it only
    /// receives what Cairn already knows about an activity.
    let garmin: GarminClient
    let garminSync: GarminSyncTracker
    /// Les zones de FC et de puissance de chaque sortie, copiées de Garmin.
    let garminZones: GarminZonesFetcher
    /// Gardé pour le remplissage des zones, qui travaille dans son propre contexte.
    let zonesContainer: ModelContainer
    let edits: EditPropagator
    /// Who Garmin says is signed in, nil when nobody is. Read from the
    /// Keychain at launch, so it costs no request.
    var garminAccountName: String?
    var isGarminConnected: Bool
    let mirrorProgress: MirrorProgress
    /// Kept alive for the life of the app, not just through `init`: its
    /// `start()` registers a `NotificationCenter` observer whose closure
    /// captures no `self`, so nothing else would keep this instance around —
    /// `deinit` would unsubscribe it the moment a purely-local variable went
    /// out of scope. See `MirrorRecorder`'s own doc comment.
    let mirrorRecorder: MirrorRecorder
    /// Held so `forgetMirror()` can wipe it — see `MirrorBootstrapCursor.clear()`.
    /// `mirror` itself keeps its own copy internally; both wrap the same
    /// `UserDefaults.standard`, so clearing this one clears what `mirror`
    /// reads too.
    let mirrorCursor: MirrorBootstrapCursor
    var mirrorTask: Task<Void, Never>?
    /// La boucle qui relève le miroir toute seule. Voir `startMirrorPolling()`.
    var mirrorPollTask: Task<Void, Never>?
    /// Quand la dernière relève automatique est partie, pour ne pas en lancer
    /// deux coup sur coup lorsqu'on passe d'une fenêtre à l'autre.
    var lastAutomaticMirrorSync: Date?

    var isAuthenticated: Bool
    var hasCredentials: Bool
    var athleteName: String?
    var errorMessage: String?
    var mirrorErrorMessage: String?
    /// Où en est le chiffrement du journal vers Supabase, pour les réglages.
    var journalEncryption: JournalEncryptionState = .unknown

    var runningTask: Task<Void, Never>?
    let defaults = UserDefaults.standard

    /// Installed by `RootView` so the menu bar can reach the window's own state.
    ///
    /// Nil whenever the screen on display gives the command nothing to act on —
    /// no window, no selection, a section the command does not belong to —
    /// which is exactly what greys the menu item out. See `RootView.menuState`.
    var requestNewActivity: (() -> Void)?
    var requestEditSelection: (() -> Void)?
    var requestDeleteSelection: (() -> Void)?
    var requestToggleFavorite: (() -> Void)?
    var requestImportGPX: (() -> Void)?
    var requestExportGPX: (() -> Void)?
    var requestExportJournalPDF: (() -> Void)?
    /// Un tag cliqué dans une note : le journal, filtré sur lui.
    var requestShowJournalTag: ((JournalTag) -> Void)?
    var requestToggleListStyle: (() -> Void)?
    var requestShowKeyboardHelp: (() -> Void)?
    /// Opens the confirmation, not the resync itself: see
    /// `ResyncEverythingConfirmation`.
    var requestResyncEverything: (() -> Void)?
    /// Whether every selected activity is already starred, for the menu item
    /// to say what it will do.
    var selectionIsFavorite = false

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
        let garmin = GarminClient(store: store)
        self.garmin = garmin
        let garminSync = GarminSyncTracker(client: garmin, defaults: .standard)
        self.garminSync = garminSync
        self.garminZones = GarminZonesFetcher(client: garmin)
        self.zonesContainer = container
        self.edits = EditPropagator(strava: client, garmin: garmin, garminSync: garminSync)
        let garminTokens = store.garminTokens()
        self.isGarminConnected = garminTokens != nil
        self.garminAccountName = garminTokens?.displayName
        self.engine = SyncEngine(
            source: client, container: container, progress: progress
        )
        self.isAuthenticated = store.tokens() != nil
        self.hasCredentials = store.credentials() != nil
        // The application's own cache folder, named here rather than defaulted
        // inside the store: see `JournalStore.init`'s own `attachmentsBase`
        // parameter, and `JournalAttachmentCache.materialise` before it.
        self.journal = JournalStore(
            container: container, attachmentsBase: JournalAttachmentCache.vaultRoot
        )

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

        journalLock.avantDeVerrouiller = { [journal] in journal.saveNow() }
        watchForJournalLock()
    }

    /// What closes the journal without anyone asking: Cairn left for a while,
    /// the screen locking, the Mac going to sleep, the session switched away.
    /// The rules themselves are `JournalLock`'s; this only tells it when.
    func watchForJournalLock() {
        let lock = journalLock
        let app = NotificationCenter.default
        lockObservers.append(app.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { lock.applicationQuittee() } })
        lockObservers.append(app.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { lock.applicationRevenue() } })

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            lockObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { lock.ecranVerrouille() }
            })
        }
        lockObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { lock.ecranVerrouille() } })
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

    /// After anything that may have signed in or out of Garmin — a refresh
    /// Garmin refused clears the tokens from inside the client.
    func refreshGarminState() {
        let tokens = store.garminTokens()
        isGarminConnected = tokens != nil
        garminAccountName = tokens?.displayName
    }

    func disconnectGarmin() {
        Task { [garmin] in
            try? await garmin.signOut()
            refreshGarminState()
        }
    }

    /// Full sync: summaries, gear, then every pending stream.
    func syncNow() {
        runSync { [engine] in try await engine.syncAll() }
    }

    /// The cheap pass only — a couple of requests whatever the history size.
    func syncSummariesOnly() {
        runSync { [engine] in
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

    static let syncOnLaunchKey = "syncsOnLaunch"

    func syncOnLaunch() {
        restoreLastSyncDate()
        pushMirrorOnLaunch()
        startMirrorPolling()
        // Les zones des anciennes sorties, doucement, en fond ; puis, les plus
        // récentes connues, l'écart avec celles de Strava.
        if isGarminConnected {
            garminZones.startBackfill(container: zonesContainer) { [weak self] in
                await self?.checkZoneDrift()
            }
        }
        guard syncsOnLaunch, isAuthenticated else { return }
        syncSummariesOnly()
    }

    /// Si le lancement compare les zones de FC de Strava à celles de Garmin.
    /// Le réglage n'a de sens, et ne s'affiche, qu'avec les deux comptes.
    static let alertsOnZoneDriftKey = "alertsOnZoneDrift"

    var alertsOnZoneDrift: Bool {
        defaults.object(forKey: Self.alertsOnZoneDriftKey) as? Bool ?? true
    }

    /// L'écart trouvé au lancement, que la fenêtre présente en alerte. Rien
    /// n'est mémorisé : tant que Strava n'est pas corrigé, l'alerte revient à
    /// chaque lancement — le réglage est là pour la couper.
    var zoneDrift: HeartRateZoneDrift?

    func checkZoneDrift() async {
        guard alertsOnZoneDrift, isGarminConnected, isAuthenticated,
              let latest = HeartRateZoneDrift.latestGarminZones(in: ModelContext(zonesContainer)),
              let strava = try? await client.athleteZones().heart_rate
        else { return }
        zoneDrift = HeartRateZoneDrift.compare(
            garminFloors: latest.floors,
            stravaFloors: HeartRateZoneDrift.stravaFloors(strava.zones),
            activityDate: latest.date
        )
    }

    /// Combien de temps sépare deux relèves du miroir.
    ///
    /// Cinq minutes. Une relève à vide coûte une requête par table, sept en
    /// tout : chacune s'arrête à sa première page incomplète, et un curseur
    /// qui n'a rien à lire ne lit rien. C'est assez court pour qu'une note
    /// écrite sur le téléphone arrive pendant qu'on regarde ailleurs, assez
    /// long pour qu'une journée entière d'application ouverte ne fasse pas
    /// mille appels.
    static let mirrorPollInterval: Duration = .seconds(300)

    /// Deux relèves automatiques ne se suivent jamais de plus près que cela.
    ///
    /// Passer d'une fenêtre à l'autre et revenir ne doit pas relancer une
    /// lecture qui vient de finir.
    static let mirrorPollFloor: TimeInterval = 30

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
    func runSync(_ operation: @escaping @Sendable () async throws -> Void) {
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

    /// Run by the pane's own task, not detached from it: opening the next
    /// outing cancels this one, and a request not yet sent never leaves.
    /// Detached, `j` held down in the list queued a Strava request for every
    /// outing it went past, each one spending quota on a pane already gone.
    func loadDetail(stravaID: Int64) async {
        await Log.sync.attempt("détail de la sortie \(stravaID)") { [engine] in
            try await engine.fetchDetailIfNeeded(stravaID: stravaID)
        }
        guard !Task.isCancelled else { return }
        // Separately, and after: a failure to fetch the detail must not cost
        // the charts, and neither is worth surfacing as an error — the pane
        // says what is missing on its own.
        await Log.sync.attempt("courbes de la sortie \(stravaID)") { [engine] in
            try await engine.fetchStreamsIfNeeded(stravaID: stravaID)
        }
    }

}

enum JournalEncryptionState: Equatable {
    /// Pas encore demandé, ou le miroir n'est pas connecté.
    case unknown
    /// Le script SQL n'a pas été passé.
    case unavailable
    case plain
    case sealed
    /// Chiffré, sans la clé sur ce Mac.
    case locked
}
