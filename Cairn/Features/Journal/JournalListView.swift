import SwiftUI

/// The notes, newest first.
///
/// A plain `List` rather than the activity list's `Table`: a note has one
/// column worth showing — what it says — and the tags under it are chips, not
/// a sortable field.
struct JournalListView: View {
    let notes: [JournalNote]
    /// The live search text, so a row can show the passage that matched rather
    /// than its first line.
    let query: String
    /// Why there is nothing to list, when the folder itself is the reason.
    let loadError: String?
    @Binding var selection: DateKey?
    var focusRequest: Int
    let onCommand: (VimCommand) -> Bool
    let onSelectTag: (JournalTag) -> Void
    /// `e` or Return: hand the keyboard to the editor in the right-hand pane.
    let onOpenEditor: () -> Void
    /// `x`: ask for the note to go, which the window confirms first.
    let onDelete: (DateKey) -> Void

    var body: some View {
        List(notes, selection: $selection) { note in
            row(note)
                .tag(note.date)
        }
        .listStyle(.inset)
        .overlay {
            if notes.isEmpty {
                // The folder first: an empty list because the vault is not
                // there is not an empty journal, and inviting ⌘N would open a
                // note nothing can write. Only when the list is empty — a
                // deletion that would not go through also sets this message,
                // and that one must not blank out the notes still listed.
                if let loadError {
                    ContentUnavailableView(
                        "Dossier indisponible",
                        systemImage: "folder.badge.questionmark",
                        description: Text(loadError)
                    )
                } else {
                    ContentUnavailableView(
                        "Aucune note",
                        systemImage: "text.book.closed",
                        description: Text(
                            query.isEmpty
                                ? "⌘N ouvre la note du jour."
                                : "Aucune note ne contient « \(query) »."
                        )
                    )
                }
            }
        }
        .vimKeys(focusRequest: focusRequest) { command in
            switch command {
            case let .move(delta):
                return moveSelection(by: delta)
            case .first:
                selection = notes.first?.date
                return true
            case .last:
                selection = notes.last?.date
                return true
            case let .halfPage(down):
                return moveSelection(
                    by: down ? VimMotion.halfPageRows : -VimMotion.halfPageRows
                )
            // `e` means "edit" everywhere; here what gets edited is the note.
            case .edit, .editNotes:
                guard selection != nil else { return false }
                onOpenEditor()
                return true
            // Same for `x`: the thing this screen can delete is a note.
            case .delete:
                guard let selection else { return false }
                onDelete(selection)
                return true
            default:
                return onCommand(command)
            }
        }
        .onKeyPress(.return) {
            guard selection != nil else { return .ignored }
            onOpenEditor()
            return .handled
        }
    }

    private func moveSelection(by delta: Int) -> Bool {
        let current = selection.flatMap { key in
            notes.firstIndex { $0.date == key }
        }
        guard let destination = VimMotion.destination(
            from: current, delta: delta, count: notes.count
        ) else { return false }
        selection = notes[destination].date
        return true
    }

    private func row(_ note: JournalNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.fullDate(note.date.date()))
                .font(.headline)
            Text(note.excerpt(matching: query) ?? note.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !note.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(note.tags.sorted()) { tag in
                        JournalTagChip(tag: tag) { onSelectTag(tag) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// One tag as a chip, quiet like `ActivityLabelChip` and clickable like a
/// filter — which is what it is: the editor beside it is plain text, so this is
/// where a tag can be acted on.
struct JournalTagChip: View {
    let tag: JournalTag
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(tag.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Ne garder que les notes portant \(tag.displayName)")
    }
}
