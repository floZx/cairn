import SwiftUI
import AppKit

/// Where the journal's notes live, and nothing else.
///
/// The count is not decoration: it is the only immediate confirmation that the
/// folder just chosen is the one holding the notes, rather than the vault's
/// parent directory.
struct JournalSettingsView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Form {
            Section {
                LabeledContent("Dossier") {
                    Text(app.journal.folder?.path ?? "aucun dossier choisi")
                        .foregroundStyle(
                            app.journal.folder == nil ? .secondary : .primary
                        )
                        .lineLimit(2)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choisir…") { chooseFolder() }
                    if app.journal.folder != nil {
                        Button("Retirer") { app.journal.choose(nil) }
                    }
                }
                if app.journal.folder != nil {
                    LabeledContent("Notes trouvées") {
                        Text("\(app.journal.notes.count)")
                            .monospacedDigit()
                    }
                }
                if let message = app.journal.loadError {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Dossier des notes")
            } footer: {
                Text(footer)
            }
        }
        .formStyle(.grouped)
    }

    private var footer: String {
        """
        Une note par jour, nommée AAAA-MM-JJ.md à la racine du dossier — le \
        format des notes du jour d'Obsidian, dont un dossier existant s'ouvre \
        tel quel. Les autres fichiers du dossier sont ignorés, et les \
        sous-dossiers ne sont pas parcourus.

        Le journal n'entre pas dans la sauvegarde iCloud de Cairn : le dossier \
        est déjà sur iCloud Drive, et l'y recopier ne protégerait de rien.
        """
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"
        panel.message = "Choisissez le dossier qui contient vos notes du jour"
        panel.directoryURL = app.journal.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.journal.choose(url)
    }
}
