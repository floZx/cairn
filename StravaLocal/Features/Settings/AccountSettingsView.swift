import SwiftUI

/// Strava API credentials and the OAuth connection.
struct AccountSettingsView: View {
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
