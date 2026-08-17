import SwiftUI

/// What the journal holds, and where it holds it.
///
/// There is no folder to choose any more: the notes live in the base like
/// everything else, and the folder that used to hold them is read once at the
/// first launch and then forgotten. The count is what is left of the old
/// confirmation, and it still earns its place — it is the immediate proof that
/// the recovery found the notes.
struct JournalSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    /// The recovery's own report — `JournalSettings.importNoticeKey`, written
    /// once by `StoreMaintenance.run` the very first time it recovers a
    /// journal folder, absent on every launch that finds nothing to say.
    /// This is the one screen a reader would open to check on a note the
    /// recovery flagged, so it is where that sentence has to surface.
    @AppStorage(JournalSettings.importNoticeKey) private var importNotice = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes") {
                    Text("\(app.journal.notes.count)")
                        .monospacedDigit()
                }
            } header: {
                Text("Journal")
            } footer: {
                Text(footer)
            }

            if !importNotice.isEmpty {
                Section {
                    Text(importNotice)
                } header: {
                    Text("Reprise")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Ce que la sauvegarde en fait n'est pas dit ici : l'export Markdown
    /// existe (`JournalMarkdownExport`) mais personne ne l'appelle encore, et
    /// une promesse en avance d'une tâche est une promesse fausse.
    private var footer: String {
        """
        Les notes du journal vivent dans la base de Cairn, et entrent donc \
        dans la sauvegarde.
        """
    }
}
