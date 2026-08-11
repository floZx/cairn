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
    /// What the header has to say about this note, decided by `JournalNotice`
    /// rather than here: which wording, and which buttons, is the one thing in
    /// this view where being wrong loses text.
    let notice: JournalNotice?
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
        // Only where there is a field to aim at: `e` or Return on an unreadable
        // row would otherwise ask for focus nothing can take.
        .onChange(of: focusRequest) { _, _ in
            guard note.isReadable else { return }
            editorFocused = true
        }
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
            if let conflict = notice?.conflict { banner(conflict) }
            if let failure = notice?.failure { self.failure(failure) }
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
    private func banner(_ conflict: JournalNotice.Conflict) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(conflict.message)
                .font(.callout)
            Spacer(minLength: 8)
            if conflict.offersReload {
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
    /// only something to know. The second line is the one that matters — a
    /// journal that has stopped taking a keystroke, or stopped changing note,
    /// with nothing said is read as a broken app rather than as text held back
    /// for its own safety. Which of the two it is, `JournalNotice` decides.
    private func failure(_ failure: JournalNotice.Failure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(failure.message)
            }
            Text(failure.consequence)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
