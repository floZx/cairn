import SwiftUI
import SwiftData

/// Sync state and the actions that drive it.
struct SyncSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Query private var activities: [Activity]

    var body: some View {
        Form {
            Section("État") {
                LabeledContent("Activités locales", value: "\(activities.count)")
                LabeledContent("Synchronisation", value: app.progress.statusText)
                LabeledContent(
                    "Courbes en attente",
                    value: app.progress.pendingStreams == 0
                        ? "aucune" : "\(app.progress.pendingStreams) activités"
                )
                LabeledContent(
                    "À compléter",
                    value: app.progress.pendingBackfill == 0
                        ? "aucune" : "\(app.progress.pendingBackfill) activités"
                )
                if let quota = app.progress.quota {
                    LabeledContent(
                        "Quota Strava",
                        value: "\(quota.shortTermUsage)/\(quota.shortTermLimit) · "
                            + "\(quota.dailyUsage)/\(quota.dailyLimit) aujourd'hui"
                    )
                }
                if let fraction = app.progress.fractionCompleted {
                    ProgressView(value: fraction)
                }
            }

            Section("Au lancement") {
                Toggle(
                    "Rechercher les nouvelles activités",
                    isOn: Binding(
                        get: { app.syncsOnLaunch },
                        set: { app.syncsOnLaunch = $0 }
                    )
                )
            }

            Section {
                Button("Synchroniser maintenant") { app.syncNow() }
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Importer seulement les résumés") { app.syncSummariesOnly() }
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Resynchroniser tout") { app.resyncEverything() }
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                if app.progress.isRunning {
                    Button("Interrompre", role: .cancel) { app.cancelSync() }
                }
            } footer: {
                Text("""
                    Les traces détaillées coûtent une requête par activité. Strava \
                    autorise 200 requêtes par quart d'heure et 2 000 par jour : un \
                    gros historique s'importe donc en plusieurs fois. L'import \
                    reprend automatiquement là où il s'est arrêté.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            DiscardedActivitiesSection()
        }
        .formStyle(.grouped)
    }
}
