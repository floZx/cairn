import SwiftUI
import SwiftData

struct SettingsScene: View {
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label("Compte", systemImage: "person.crop.circle") }
            SyncSettingsView()
                .tabItem { Label("Synchronisation", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 380)
    }
}

private struct AccountSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $clientID)
                SecureField("Client Secret", text: $clientSecret)
                Button("Enregistrer les identifiants") {
                    app.saveCredentials(clientID: clientID, clientSecret: clientSecret)
                }
                .disabled(clientID.isEmpty || clientSecret.isEmpty)
            } header: {
                Text("Application Strava")
            } footer: {
                Text("""
                    Créez une application sur strava.com/settings/api en indiquant \
                    « localhost » comme Authorization Callback Domain, puis recopiez \
                    ici son Client ID et son Client Secret. Ils sont conservés dans \
                    le trousseau macOS.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Connexion") {
                if app.isAuthenticated {
                    LabeledContent("État", value: app.athleteName ?? "Connecté")
                    Button("Se déconnecter", role: .destructive) { app.disconnect() }
                } else {
                    Button {
                        isConnecting = true
                        Task {
                            await app.connect()
                            isConnecting = false
                        }
                    } label: {
                        if isConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Se connecter à Strava…")
                        }
                    }
                    .disabled(!app.hasCredentials || isConnecting)
                }
            }

            if let message = app.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            clientID = app.store.credentials()?.clientID ?? ""
            clientSecret = app.store.credentials()?.clientSecret ?? ""
        }
    }
}

private struct SyncSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Query private var activities: [Activity]
    /// Read once when the pane appears rather than on every redraw: walking the
    /// cache directory is cheap but not free.
    @State private var cacheSize = SyncSettingsView.formattedCacheSize()

    static func formattedCacheSize() -> String {
        let bytes = TileCache.diskUsage
        guard bytes > 0 else { return "aucune" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(bytes), countStyle: .file
        )
    }

    var body: some View {
        Form {
            Section("État") {
                LabeledContent("Activités locales", value: "\(activities.count)")
                LabeledContent("Synchronisation", value: app.progress.statusText)
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

            Section {
                LabeledContent("Tuiles en cache", value: cacheSize)
                Button("Vider le cache des cartes") {
                    TileCache.clear()
                    cacheSize = Self.formattedCacheSize()
                }
                .disabled(TileCache.diskUsage == 0)
            } header: {
                Text("Fonds de carte")
            } footer: {
                Text("""
                    Les tuiles des fonds topographiques sont conservées sur le \
                    disque : une zone déjà consultée ne se retélécharge pas, même \
                    après un redémarrage. Les fonds d'Apple ont leur propre cache, \
                    géré par le système.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .onAppear { cacheSize = Self.formattedCacheSize() }
    }
}
