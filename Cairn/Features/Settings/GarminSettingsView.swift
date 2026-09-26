import SwiftUI

/// The Garmin Connect sign-in: address and password, then the code Garmin
/// sends when the account asks for one.
///
/// The password lives in this view's state for as long as the form is open
/// and nowhere else — it goes to Garmin once, and the tokens that come back
/// are what the Keychain keeps.
struct GarminSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var pending: GarminPendingLogin?
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        Form {
            if app.isGarminConnected {
                Section("Connexion") {
                    LabeledContent("Compte", value: app.garminAccountName ?? "Connecté")
                    Button("Se déconnecter", role: .destructive) { app.disconnectGarmin() }
                }
            } else if pending != nil {
                Section {
                    TextField("Code", text: $code)
                        .textContentType(.oneTimeCode)
                        .onSubmit(verify)
                    HStack {
                        Button("Annuler") {
                            pending = nil
                            code = ""
                        }
                        Spacer()
                        workingButton("Valider", action: verify)
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Code de vérification")
                } footer: {
                    Text("Garmin vient d'envoyer un code, par e-mail ou par SMS selon le compte.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField("Adresse e-mail", text: $email)
                        .textContentType(.username)
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                        .onSubmit(signIn)
                    HStack {
                        Spacer()
                        workingButton("Se connecter", action: signIn)
                            .disabled(email.isEmpty || password.isEmpty)
                    }
                } header: {
                    Text("Garmin Connect")
                } footer: {
                    Text("""
                        Pour reporter sur Garmin Connect le titre, le type, la \
                        description et le matériel d'une activité. Garmin n'ayant \
                        pas d'API ouverte aux particuliers, Cairn passe par celle \
                        de son application mobile : elle peut changer sans \
                        prévenir. Le mot de passe n'est pas conservé, seule la \
                        session l'est, dans le trousseau macOS.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func workingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isWorking {
                ProgressView().controlSize(.small)
            } else {
                Text(title)
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isWorking)
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty, !isWorking else { return }
        run {
            switch try await app.garmin.login(email: email, password: password) {
            case .connected:
                password = ""
            case let .needsMFA(login):
                pending = login
            }
        }
    }

    private func verify() {
        guard let pending, !isWorking else { return }
        run {
            _ = try await app.garmin.verifyMFA(code: code, for: pending)
            self.pending = nil
            code = ""
            password = ""
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        failure = nil
        Task {
            do {
                try await work()
            } catch {
                failure = error.localizedDescription
            }
            isWorking = false
            app.refreshGarminState()
        }
    }
}
