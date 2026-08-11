import SwiftUI

/// The note, open and editable.
///
/// Plain text, always writable, with no rendered mode: a journal exists to be
/// written in, and a Markdown preview would put one keystroke between the
/// thought and the page. The `#` and the `-` stay visible, which is what makes
/// the same file readable in Obsidian.
struct JournalDetailView: View {
    let note: JournalNote
    let text: String
    let conflict: JournalReconciliation.Outcome?
    /// The message left by a save that did not go through, if any.
    ///
    /// A separate piece of state from `conflict`, and a separate line on
    /// screen: a conflict is two versions of a note to choose between, this is
    /// a note that did not reach the disk at all.
    let writeFailure: String?
    var focusRequest: Int
    let onEdit: (String) -> Void
    let onSelectTag: (JournalTag) -> Void
    let onReloadFromDisk: () -> Void
    let onDismissConflict: () -> Void
    let onLeaveEditor: () -> Void

    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if note.isReadable {
                editor
            } else {
                unreadable
            }
        }
        .onChange(of: focusRequest) { _, _ in editorFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Format.fullDate(note.date.date()))
                .font(.title3)
            if !note.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(note.tags.sorted()) { tag in
                        JournalTagChip(tag: tag) { onSelectTag(tag) }
                    }
                }
            }
            if let conflict { banner(conflict) }
            if let writeFailure { failure(writeFailure) }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        // Explicit closure rather than `set: onEdit`: passing the stored
        // closure straight in converts a non-Sendable function value into the
        // `@Sendable` one `Binding` asks for, which Swift 6 warns about.
        TextEditor(text: Binding(get: { text }, set: { onEdit($0) }))
            .font(.body)
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Escape leaves the field rather than clearing it: the list gets
            // the keyboard back and `j`/`k` work again straight away.
            .onKeyPress(.escape) {
                editorFocused = false
                onLeaveEditor()
                return .handled
            }
    }

    private var unreadable: some View {
        ContentUnavailableView(
            "Contenu illisible",
            systemImage: "exclamationmark.triangle",
            description: Text(
                """
                Ce fichier n'a pas pu être lu comme du texte. Il est laissé \
                intact : l'ouvrir ici pour écrire dessus effacerait ce qu'il \
                contient peut-être encore.
                """
            )
        )
        .frame(maxHeight: .infinity)
    }

    /// The file moved under an unsaved edit. What is on screen is the typing,
    /// never the file — losing a sentence to a sync is the one failure this
    /// whole mechanism exists to prevent.
    @ViewBuilder
    private func banner(_ conflict: JournalReconciliation.Outcome) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(
                conflict == .vanished
                    ? "Le fichier a été supprimé ailleurs. Votre texte est conservé ici."
                    : "La note a été modifiée ailleurs. Votre texte est conservé ici."
            )
            .font(.callout)
            Spacer(minLength: 8)
            if conflict == .conflict {
                Button("Recharger", action: onReloadFromDisk)
            }
            Button("Garder", action: onDismissConflict)
        }
        .padding(8)
        .background(.quaternary, in: .rect(cornerRadius: 6))
    }

    /// The last save did not go through.
    ///
    /// Two lines and no buttons, deliberately: there is nothing to choose here,
    /// only something to know. The second line is the one that matters — while
    /// a save is pending the journal refuses to change note, and a list that
    /// will not respond with nothing said is read as a broken app rather than
    /// as a note held back for its own safety.
    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
            }
            Text(
                """
                Le journal ne peut pas changer de note tant que ce texte n'est \
                pas enregistré.
                """
            )
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
