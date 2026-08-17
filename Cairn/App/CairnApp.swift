import SwiftUI
import SwiftData

@main
struct CairnApp: App {
    private let container: ModelContainer
    @State private var app: AppEnvironment
    @State private var backup = BackupController()

    init() {
        let container: ModelContainer
        do {
            container = try AppModelContainer.make()
        } catch {
            fatalError("Impossible d'ouvrir la base locale : \(error)")
        }
        self.container = container
        // Built before either write below, and deliberately so: if the mirror
        // is configured, `AppEnvironment.init` starts `MirrorRecorder` right
        // away, and starting it *after* `DemoData` or `StoreMaintenance` had
        // already written to the store would leave whatever they changed
        // invisible to the outbox forever — nothing else ever revisits it.
        // See `MirrorRecorder`'s own "When to start it" doc comment.
        let app = AppEnvironment(container: container)
        _app = State(initialValue: app)
        // No-op unless STRAVALOCAL_DEMO is set, in which case the container above
        // has already opened a separate store file — the real library is never
        // touched. Failing here is not worth a crash: the app simply starts empty.
        try? DemoData.populateIfNeeded(ModelContext(container))
        // Same reasoning as `AppModelContainer.make()`'s own use of
        // `isTesting`, which is where that question is now asked: a macOS
        // unit test bundle runs inside this application, hosted rather than
        // standalone, so `xcodebuild test` executes this very `init()` as a side
        // effect of launching for testing — not only when a test explicitly
        // constructs something. `AppModelContainer.make()` already isolates the
        // *store* file for that reason (`Cairn-tests.store`, never the real
        // library). `StoreMaintenance.run` below now also reads and writes
        // `UserDefaults.standard` — the real `journalFolderPath`, the real
        // recovery marker — and unlike the store, there is no test-only domain to
        // redirect it to without inventing one that would itself leave a file
        // behind on every run. Skipped outright instead: nothing here is a
        // target `CairnApp` unit tests exercise (see `MirrorWiringTests`' own
        // doc comment on why `CairnApp` itself is not a practical test target),
        // so skipping it changes nothing any test observes — it only stops a
        // hosted test launch from marking this Mac's real recovery done before
        // its real, non-test launch ever gets the chance to run it. Measured,
        // not hypothetical: an earlier version of this line set the real
        // `journalImportDone` to true on the very first `xcodebuild test` run.
        if !AppModelContainer.isTesting {
            // Before any view reads an activity. Failing is not worth a crash:
            // the rows keep their identity and the next launch tries again. The
            // count is discardable by design, but `try?` wraps it in its own
            // `Optional` that `@discardableResult` does not cover — hence the
            // explicit `_ =`.
            //
            // This is also the journal's one-time recovery from its old folder
            // (`StoreMaintenance.recoverJournal`) — see that function's own doc
            // comment for why it runs first, inside `run`, rather than here
            // alongside it.
            _ = try? StoreMaintenance.run(
                ModelContext(container),
                cacheDirectory: JournalAttachmentCache.vaultRoot
            )
            // `app.journal` was built above, before this line ran, on whatever
            // the store held at that moment — nothing, on the very first launch
            // after this slice ships, since the recovery had not run yet.
            // Without this, the window that opens a few lines down would show an
            // empty journal until the next relaunch, even though the recovery
            // just inserted every note. Unconditional within this branch: cheap
            // on every other launch, where the recovery has already run and this
            // simply re-reads what was already there.
            app.journal.refresh()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // Under the guard for the same reason the two `.task`s around
                // it are, and it is the one that bit: `syncOnLaunch` pushes to
                // the mirror, which refreshes the Supabase session — and a
                // Supabase refresh token is single-use and rotating. Every
                // hosted test launch spent the real one, stored the new one,
                // and left the user's actual app holding a token Supabase had
                // already retired: 401, `clearMirrorSession()`, signed out
                // with no idea why. It also runs the Strava summary pass, on
                // the real tokens and the real 2 000-a-day quota.
                .task { if !AppModelContainer.isTesting { app.syncOnLaunch() } }
                // At most once a day, and only if the library moved — see
                // `BackupPlan`. Off the main thread, so a launch never waits
                // on a hundred megabytes.
                //
                // Under the same guard as `StoreMaintenance.run` in `init`,
                // and just as literally: `BackupController.run` reads
                // `AppModelContainer.storeURL`, which spells `isTesting: false`
                // in, so a hosted test launch would point this at the real
                // 132 MB `Cairn.store` and the real iCloud Drive folder —
                // notes included, in clear Markdown, since the backup carries
                // the journal out. Only `BackupPlan.shouldBackUp` answering no
                // has stood between the suite and that, which is a schedule,
                // not a guard.
                .task { if !AppModelContainer.isTesting { backup.run(force: false) } }
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                // These two now depend on the section: an activity in the
                // list, today's note in the journal. Named for what they do
                // rather than for one of the two things they act on — a
                // « Supprimer l'activité » that sends a note to the trash is
                // the worst kind of label. The two below stay activity-worded
                // because they stayed activity-only.
                Button("Nouvel élément") { app.requestNewActivity?() }
                    .keyboardShortcut("n")
                    .disabled(app.requestNewActivity == nil)
                Button("Modifier l'activité") { app.requestEditSelection?() }
                    .keyboardShortcut("e")
                    .disabled(app.requestEditSelection == nil)
                Button("Supprimer l'élément") { app.requestDeleteSelection?() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(app.requestDeleteSelection == nil)
                Button("Favori") { app.requestToggleFavorite?() }
                    .keyboardShortcut("d")
                    .disabled(app.requestToggleFavorite == nil)
                Button("Tableau ou fiches") { app.requestToggleListStyle?() }
                    // A letter, like every other shortcut here: the digits need
                    // shift on an AZERTY keyboard.
                    .keyboardShortcut("l", modifiers: [.option, .command])
                    .disabled(app.requestToggleListStyle == nil)
            }
            // The standard placement, so Import and Export land where macOS
            // users already look for them rather than under a menu of our own.
            CommandGroup(replacing: .importExport) {
                Button("Importer des fichiers GPX…") { app.requestImportGPX?() }
                    .keyboardShortcut("i")
                    .disabled(app.requestImportGPX == nil)
                Button("Exporter la sélection en GPX…") { app.requestExportGPX?() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(app.requestExportGPX == nil)
                Button("Exporter le journal en PDF…") {
                    app.requestExportJournalPDF?()
                }
                .disabled(app.requestExportJournalPDF == nil)
            }
            CommandMenu("Strava") {
                Button("Synchroniser") { app.syncNow() }
                    .keyboardShortcut("r")
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Importer seulement les résumés") { app.syncSummariesOnly() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Resynchroniser tout") { app.resyncEverything() }
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Divider()
                Button("Interrompre la synchronisation") { app.cancelSync() }
                    .disabled(!app.progress.isRunning)
            }
        }

        Settings {
            SettingsScene()
                .environment(app)
                .modelContainer(container)
        }
    }
}
