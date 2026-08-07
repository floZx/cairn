import SwiftUI
import SwiftData

@main
struct StravaLocalApp: App {
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
