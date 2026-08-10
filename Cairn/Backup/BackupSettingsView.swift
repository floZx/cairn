import SwiftUI

/// What the backup is doing, and the one button that makes it do it now.
@MainActor @Observable
final class BackupController {
    enum Phase: Equatable {
        case idle
        case running
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastRun: Date? = BackupService.lastRun()

    /// Runs a backup off the main thread.
    ///
    /// - Parameter force: true for the button, false at launch — which lets
    ///   `BackupPlan` decide, and usually decide against.
    func run(force: Bool) {
        guard phase != .running else { return }
        phase = .running
        let store = AppModelContainer.storeURL
        let photos = AppModelContainer.externalStorageURL
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try BackupService.run(store: store, photos: photos, force: force) }
            }.value
            switch result {
            case let .success(date):
                if let date { lastRun = date }
                phase = .idle
            case let .failure(error):
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

struct BackupSettingsView: View {
    @State private var controller = BackupController()

    var body: some View {
        Form {
            Section {
                LabeledContent("Dernière sauvegarde") {
                    Text(controller.lastRun.map(Format.shortDate) ?? "jamais")
                        .foregroundStyle(controller.lastRun == nil ? .secondary : .primary)
                        .monospacedDigit()
                }
                if case .running = controller.phase {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Copie en cours…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sauvegarder maintenant") { controller.run(force: true) }
                }
                if case let .failed(message) = controller.phase {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Sauvegarde iCloud")
            } footer: {
                Text(footer)
            }
        }
        .formStyle(.grouped)
    }

    private var footer: String {
        guard let destination = BackupService.destination else {
            return "iCloud Drive est introuvable sur ce Mac. Activez-le dans "
                + "Réglages Système pour que la sauvegarde ait où aller."
        }
        return """
            Le journal et les photos sont copiés dans \(destination.lastPathComponent) \
            sur iCloud Drive, une fois par jour au démarrage et seulement si \
            quelque chose a changé. Les trois dernières versions sont \
            conservées. Le catalogue Open Food Facts n'en fait pas partie : il \
            se retélécharge.
            """
    }
}
