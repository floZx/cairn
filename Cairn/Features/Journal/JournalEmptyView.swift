import SwiftUI

/// What the section shows before a folder has been chosen.
struct JournalEmptyView: View {
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Une note par jour")
                .font(.title2)
            Text(
                """
                Choisissez le dossier où vivent vos notes. Une note par jour, \
                nommée AAAA-MM-JJ.md — c'est le format des notes du jour \
                d'Obsidian, donc un dossier existant s'ouvre tel quel.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
            Button("Choisir un dossier…", action: onChooseFolder)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
