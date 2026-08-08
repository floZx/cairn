import SwiftUI
import SwiftData

@main
struct CairnApp: App {
    private let container: ModelContainer
    @State private var app: AppEnvironment

    init() {
        let container: ModelContainer
        do {
            container = try AppModelContainer.make()
        } catch {
            fatalError("Impossible d'ouvrir la base locale : \(error)")
        }
        self.container = container
        // No-op unless STRAVALOCAL_DEMO is set, in which case the container above
        // has already opened a separate store file — the real library is never
        // touched. Failing here is not worth a crash: the app simply starts empty.
        try? DemoData.populateIfNeeded(ModelContext(container))
        // Before any view reads an activity. Failing is not worth a crash: the
        // rows keep their identity and the next launch tries again. The count is
        // discardable by design, but `try?` wraps it in its own `Optional` that
        // `@discardableResult` does not cover — hence the explicit `_ =`.
        _ = try? StoreMaintenance.run(ModelContext(container))
        _app = State(initialValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { app.syncOnLaunch() }
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Nouvelle activité") { app.requestNewActivity?() }
                    .keyboardShortcut("n")
                    .disabled(app.requestNewActivity == nil)
                Button("Modifier l'activité") { app.requestEditSelection?() }
                    .keyboardShortcut("e")
                    .disabled(app.requestEditSelection == nil)
                Button("Supprimer l'activité") { app.requestDeleteSelection?() }
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
