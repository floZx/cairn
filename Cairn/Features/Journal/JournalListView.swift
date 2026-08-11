import SwiftUI

/// The days, newest first.
///
/// A plain `List` rather than the activity list's `Table`: a note has one
/// column worth showing — what it says — and the tags under it are chips, not
/// a sortable field.
struct JournalListView: View {
    let days: [JournalDay]
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

    /// The note to open on arriving in the section, or nil to leave things be.
    ///
    /// Only the newest, and only when nothing is chosen. A section that opens
    /// on an empty pane wastes the window, and worse, leaves the keys that act
    /// on the selection — `e`, `n`, `⏎`, `x` — doing nothing at all, which
    /// reads as the shortcuts being broken rather than as nothing being
    /// selected. Overriding a choice the user made, or made a point of
    /// clearing, would be worse still; hence the `current == nil` guard.
    static func initialSelection(
        days: [JournalDay], current: DateKey?
    ) -> DateKey? {
        guard current == nil else { return nil }
        return days.first?.date
    }

    var body: some View {
        List(days, selection: $selection) { day in
            row(day)
                .tag(day.date)
        }
        .listStyle(.inset)
        // On appearance alone, which here means on entering the section: no
        // `.id(…)` rebuilds this view for a search or a tag, so Escape can
        // clear the selection without the next pass putting it straight back.
        // The binding is the guarded one, so a note whose write failed still
        // refuses to be left.
        .onAppear {
            if let first = Self.initialSelection(days: days, current: selection) {
                selection = first
            }
        }
        .overlay {
            if days.isEmpty {
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
                selection = days.first?.date
                return true
            case .last:
                selection = days.last?.date
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
            // Same for `x`: the thing this screen can delete is a note *file*.
            // A day that is in the list only because an outing wrote something
            // has no file to trash, and an outing's note is edited where it
            // lives. Refused rather than swallowed, so the press falls through
            // instead of raising a dialog that would do nothing.
            case .delete:
                guard let selection, days.first(where: { $0.date == selection })
                    .map({ !$0.note.isEmpty }) == true
                else { return false }
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
            days.firstIndex { $0.date == key }
        }
        guard let destination = VimMotion.destination(
            from: current, delta: delta, count: days.count
        ) else { return false }
        selection = days[destination].date
        return true
    }

    private func row(_ day: JournalDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.fullDate(day.date.date()))
                .font(.headline)
            Text(day.excerpt(matching: query) ?? day.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !day.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(day.tags.sorted()) { tag in
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
            // The bare name: the capsule already says this is a tag, and the
            // sidebar dropped its hash for the same reason.
            Text(tag.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Ne garder que les notes portant \(tag.name)")
    }
}
