import SwiftUI

/// Supabase project, sign-in, bootstrap and status — the mirror's own
/// settings tab, on the pattern `AccountSettingsView` and `SyncSettingsView`
/// already set for Strava: credentials in one section, connection in the
/// next, actions and state in a third.
struct MirrorSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var projectURL = ""
    @State private var anonKey = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    /// `MirrorRecorder.failureCount` is a plain `static var`, not
    /// `@Observable` — reading it once in `onAppear` would freeze whatever it
    /// happened to be the moment the tab opened. Polled instead, at a slow
    /// enough interval that it costs nothing: the counter only ever moves on
    /// a local disk write failing, not a network event, so there is no
    /// reason to poll faster than a person can reread the screen.
    @State private var outboxFailureCount = 0

    var body: some View {
        Form {
            Section {
                TextField(
                    "URL du projet", text: $projectURL,
                    prompt: Text("https://xxxxxxxx.supabase.co")
                )
                SecureField("Clé anon", text: $anonKey)
                Button("Enregistrer les identifiants") {
                    app.saveMirrorCredentials(projectURL: projectURL, anonKey: anonKey)
                }
                .disabled(projectURL.isEmpty || anonKey.isEmpty)
            } header: {
                Text("Projet Supabase")
            } footer: {
                Text("""
                    Créez un projet sur supabase.com, appliquez le schéma décrit dans \
                    supabase/README.md, puis recopiez ici son URL et sa clé anon. Elles \
                    sont conservées dans le trousseau macOS.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Connexion") {
                if app.isMirrorSignedIn {
                    LabeledContent("État", value: "Connecté")
                } else {
                    TextField("Adresse", text: $email)
                    SecureField("Mot de passe", text: $password)
                    Button {
                        isSigningIn = true
                        Task {
                            await app.signInMirror(email: email, password: password)
                            isSigningIn = false
                        }
                    } label: {
                        if isSigningIn {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Se connecter")
                        }
                    }
                    .disabled(
                        !app.isMirrorConfigured || email.isEmpty || password.isEmpty
                            || isSigningIn
                    )
                }
            }

            Section {
                LabeledContent("État", value: app.mirrorProgress.statusText)
                if outboxFailureCount > 0 {
                    LabeledContent(
                        "Écritures locales non enregistrées",
                        value: "\(outboxFailureCount)"
                    )
                }
                Button("Lancer l'amorçage") { app.startBootstrap() }
                    .disabled(
                        !app.isMirrorConfigured || !app.isMirrorSignedIn
                            || app.mirrorProgress.isRunning
                    )
                Button("Pousser les modifications") { app.pushNow() }
                    .disabled(
                        !app.isMirrorConfigured || !app.isMirrorSignedIn
                            || app.mirrorProgress.isRunning
                    )
                if app.mirrorProgress.isRunning {
                    Button("Interrompre", role: .cancel) { app.cancelMirror() }
                }
            } header: {
                Text("Amorçage et envoi")
            } footer: {
                Text("""
                    L'amorçage envoie toute la bibliothèque une première fois ; il \
                    reprend là où il s'est arrêté si vous l'interrompez. Ensuite, chaque \
                    modification locale est envoyée au fil de l'eau.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let message = app.mirrorErrorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Oublier ce miroir", role: .destructive) { app.forgetMirror() }
            } footer: {
                Text("""
                    Efface le projet et la session enregistrés sur ce Mac. N'affecte \
                    aucune donnée locale, et rien n'est supprimé côté Supabase.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            projectURL = app.store.mirrorCredentials()?.projectURL.absoluteString ?? ""
            anonKey = app.store.mirrorCredentials()?.anonKey ?? ""
        }
        .task {
            while !Task.isCancelled {
                outboxFailureCount = MirrorRecorder.failureCount
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
