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
    @State private var phrase = ""
    @State private var confirmation = ""
    @State private var enChiffrement = false
    @State private var messageChiffrement: String?

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
                Button("Synchroniser") { app.syncMirrorNow() }
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
                    modification locale part au lancement suivant, ou tout de suite avec \
                    « Pousser les modifications ».
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if app.isMirrorSignedIn {
                chiffrement
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
        .task { await app.refreshJournalEncryption() }
        .task {
            while !Task.isCancelled {
                outboxFailureCount = MirrorRecorder.failureCount
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Chiffrement du journal

    @ViewBuilder
    private var chiffrement: some View {
        Section {
            switch app.journalEncryption {
            case .unknown:
                LabeledContent("État", value: "…")
            case .unavailable:
                Text("Passez d'abord le script supabase/012-journal-chiffre.sql dans l'éditeur SQL du projet.")
                    .foregroundStyle(.secondary)
            case .sealed:
                LabeledContent("État", value: "Chiffré, clé présente sur ce Mac")
            case .plain:
                SecureField("Phrase secrète", text: $phrase)
                SecureField("Confirmation", text: $confirmation)
                boutonChiffrement(
                    "Chiffrer le journal",
                    actif: phrase.count >= 8 && phrase == confirmation
                )
            case .locked:
                LabeledContent("État", value: "Chiffré, phrase à saisir sur ce Mac")
                SecureField("Phrase secrète", text: $phrase)
                boutonChiffrement("Ouvrir le journal chiffré", actif: !phrase.isEmpty)
            }
            if let messageChiffrement {
                Label(messageChiffrement, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Chiffrement du journal")
        } footer: {
            Text("""
                Les notes du journal partent chiffrées vers Supabase : ni l'hébergeur ni \
                personne ayant accès au compte ne peut les lire sans la phrase. Elle se \
                tape une fois par appareil. **Oubliée, la copie en ligne devient \
                illisible** — les notes restent en clair sur ce Mac et dans la \
                sauvegarde iCloud. Les photos jointes ne sont pas chiffrées.
                """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func boutonChiffrement(_ titre: String, actif: Bool) -> some View {
        Button {
            enChiffrement = true
            messageChiffrement = nil
            Task {
                messageChiffrement = await app.setJournalPassphrase(phrase)
                if messageChiffrement == nil {
                    phrase = ""
                    confirmation = ""
                }
                enChiffrement = false
            }
        } label: {
            if enChiffrement {
                ProgressView().controlSize(.small)
            } else {
                Text(titre)
            }
        }
        .disabled(!actif || enChiffrement || app.mirrorProgress.isRunning)
    }
}
