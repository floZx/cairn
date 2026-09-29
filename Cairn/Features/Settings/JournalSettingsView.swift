import SwiftUI

/// What the journal holds, and how it is locked.
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

            lockSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var lockSection: some View {
        @Bindable var lock = app.journalLock
        Section {
            Toggle("Verrouiller le journal", isOn: $lock.isEnabled)
            if lock.isEnabled {
                Picker("Le refermer", selection: $lock.delay) {
                    ForEach(JournalLockDelay.allCases) { delay in
                        Text(delay.displayName).tag(delay)
                    }
                }
            }
        } header: {
            Text("Verrou")
        } footer: {
            Text("""
                Touch ID ou le mot de passe de votre session pour l'ouvrir ; \
                il se referme aussi quand l'écran se verrouille ou que le Mac \
                s'endort, et à la demande avec ⌃⌘L. Il protège d'un regard, \
                pas davantage : sur ce Mac, les notes ne sont pas chiffrées. \
                Vers le web, elles peuvent l'être — voir l'onglet Supabase.
                """)
        }
    }

    /// La tâche 6 avait dû taire la moitié de cette phrase : l'export
    /// Markdown existait déjà (`JournalMarkdownExport`) mais rien ne
    /// l'appelait encore, et une promesse en avance d'une tâche est une
    /// promesse fausse. `BackupService.run` l'appelle désormais — dette de
    /// cette tâche-là, payée par la tâche 8.
    private var footer: String {
        """
        Les notes du journal vivent dans la base de Cairn, et entrent donc \
        dans la sauvegarde ; elle en tient aussi un export Markdown, à côté, \
        pour les relire sans Cairn au besoin.
        """
    }
}
