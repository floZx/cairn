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
        }
        .formStyle(.grouped)
    }

    private var footer: String {
        """
        Les notes du journal vivent dans la base de Cairn, et entrent donc \
        dans la sauvegarde — qui en écrit aussi une copie en Markdown, une \
        note par jour nommée AAAA-MM-JJ.md, qu'Obsidian ouvre telle quelle.
        """
    }
}
