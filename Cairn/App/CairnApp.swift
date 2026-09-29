import SwiftUI
import SwiftData

@main
struct CairnApp: App {
    private let container: ModelContainer
    @State private var app: AppEnvironment
    @State private var backup = BackupController()
    @AppStorage(ActivityCardThumbnail.storageKey)
    private var cardThumbnail: ActivityCardThumbnail = .trace
    /// Set by the main window while it is the focused scene: in the settings
    /// window, ⌘⌫ or ⌘D must not reach the library behind it.
    @FocusedValue(\.isMainWindow) private var isMainWindow

    init() {
        let container: ModelContainer
        do {
            container = try AppModelContainer.make()
        } catch {
            fatalError("Impossible d'ouvrir la base locale : \(error)")
        }
        self.container = container
        // One window: « Nouvelle fenêtre » is already gone from the menu, and
        // the menu commands act on the window that installed them last. The
        // tab bar's own « + » and its Présentation items went with tabbing.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Built before either write below, and deliberately so: if the mirror
        // is configured, `AppEnvironment.init` starts `MirrorRecorder` right
        // away, and starting it *after* `DemoData` or `StoreMaintenance` had
        // already written to the store would leave whatever they changed
        // invisible to the outbox forever — nothing else ever revisits it.
        // See `MirrorRecorder`'s own "When to start it" doc comment.
        let app = AppEnvironment(container: container)
        _app = State(initialValue: app)
        // No-op unless CAIRN_DEMO is set, in which case the container above
        // has already opened a separate store file — the real library is never
        // touched. Failing here is not worth a crash: the app simply starts empty.
        try? DemoData.populateIfNeeded(ModelContext(container))
        // Same reasoning as `AppModelContainer.make()`'s own use of
        // `isTesting`: a macOS unit test bundle runs inside this application,
        // so `xcodebuild test` executes this very `init()`. The store is
        // already a throwaway one under test, but the maintenance also
        // rebuilds the journal's picture cache in the application's real cache
        // folder — skipped outright, since nothing here is a target the unit
        // tests exercise.
        if !AppModelContainer.isTesting {
            // Before any view reads an activity. Failing is not worth a crash:
            // the rows keep their identity and the next launch tries again.
            Log.maintenance.attempt("maintenance du lancement") {
                try StoreMaintenance.run(
                    ModelContext(container),
                    cacheDirectory: JournalAttachmentCache.vaultRoot
                )
            }
            // `app.journal` was built above, before this line ran: a day the
            // maintenance just folded would otherwise show twice until the
            // next relaunch. Cheap when nothing changed.
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
                // These two depend on the section: an activity in the list,
                // today's note in the journal. Named for what they do rather
                // than for one of the two things they act on — a « Supprimer
                // l'activité » that sends a note to the trash is the worst
                // kind of label. The others stay activity-worded because they
                // are activity-only.
                Button("Nouvel élément") { Self.inMainWindow(app.requestNewActivity) }
                    .keyboardShortcut("n")
                    .disabled(unavailable(app.requestNewActivity))
                Button("Modifier l'activité…") { Self.inMainWindow(app.requestEditSelection) }
                    .keyboardShortcut("e")
                    .disabled(unavailable(app.requestEditSelection))
                Button("Supprimer l'élément…") { Self.deleteOrEraseLine(app.requestDeleteSelection) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(unavailable(app.requestDeleteSelection))
                Button(app.selectionIsFavorite ? "Retirer des favoris" : "Ajouter aux favoris") {
                    Self.inMainWindow(app.requestToggleFavorite)
                }
                .keyboardShortcut("d")
                .disabled(unavailable(app.requestToggleFavorite))
            }
            // Le menu Présentation, où macOS range ce qui change la façon de
            // voir sans rien changer à ce qu'on voit.
            CommandGroup(after: .toolbar) {
                Button("Tableau ou fiches") { Self.inMainWindow(app.requestToggleListStyle) }
                    // A letter, like every other shortcut here: the digits need
                    // shift on an AZERTY keyboard.
                    .keyboardShortcut("l", modifiers: [.option, .command])
                    .disabled(unavailable(app.requestToggleListStyle))
                Picker("Présentation des fiches", selection: $cardThumbnail) {
                    ForEach(ActivityCardThumbnail.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Divider()
            }
            // The standard placement, so Import and Export land where macOS
            // users already look for them rather than under a menu of our own.
            CommandGroup(replacing: .importExport) {
                Button("Importer des fichiers GPX…") { Self.inMainWindow(app.requestImportGPX) }
                    .keyboardShortcut("i")
                    .disabled(unavailable(app.requestImportGPX))
                Button("Exporter la sélection en GPX…") { Self.inMainWindow(app.requestExportGPX) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(unavailable(app.requestExportGPX))
                if !SidebarItem.journal.estMasquee {
                    Button("Exporter le journal en PDF…") {
                        Self.inMainWindow(app.requestExportJournalPDF)
                    }
                    .disabled(unavailable(app.requestExportJournalPDF))
                }
                if !SidebarItem.journal.estMasquee {
                    Divider()
                    // Comme ⌃⌘Q verrouille l'écran : la même famille de geste,
                    // pour la seule partie de Cairn qui en a un.
                    Button("Verrouiller le journal") { app.journalLock.verrouiller() }
                        .keyboardShortcut("l", modifiers: [.control, .command])
                        .disabled(!app.journalLock.isEnabled || !app.journalLock.estOuvert)
                }
            }
            CommandMenu("Strava") {
                Button("Synchroniser") { app.syncNow() }
                    .keyboardShortcut("r")
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Importer seulement les résumés") { app.syncSummariesOnly() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Resynchroniser tout…") { app.requestResyncEverything?() }
                    .disabled(
                        !app.isAuthenticated || app.progress.isRunning
                            || app.requestResyncEverything == nil
                    )
                Divider()
                Button("Interrompre la synchronisation") { app.cancelSync() }
                    .disabled(!app.progress.isRunning)
            }
            // Pas de livre d'aide : l'élément par défaut n'ouvrait qu'« Aide
            // non disponible ». L'aide-mémoire du clavier, que `?` ouvre déjà.
            CommandGroup(replacing: .help) {
                Button("Raccourcis clavier") { Self.inMainWindow(app.requestShowKeyboardHelp) }
                    .keyboardShortcut("?", modifiers: .command)
                    .disabled(unavailable(app.requestShowKeyboardHelp))
            }
        }

        Settings {
            SettingsScene()
                .environment(app)
                .environment(backup)
                .modelContainer(container)
        }
    }

    private func unavailable(_ command: (() -> Void)?) -> Bool {
        command == nil || isMainWindow != true
    }

    /// Runs a window command unless a sheet is in front: an editor open on one
    /// activity must not let ⌘⌫ delete another behind it.
    private static func inMainWindow(_ command: (() -> Void)?) {
        guard let command, NSApp.keyWindow?.sheetParent == nil else { return }
        command()
    }

    /// ⌘⌫ is also the text system's « effacer jusqu'au début de la ligne », and
    /// a menu's key equivalent reaches the menu before the text view sees the
    /// key: typing it in a note would have asked to delete the note. In a
    /// text field it keeps its text meaning.
    private static func deleteOrEraseLine(_ command: (() -> Void)?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable {
            text.deleteToBeginningOfLine(nil)
            return
        }
        inMainWindow(command)
    }
}

extension FocusedValues {
    @Entry var isMainWindow: Bool?
}
