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
    /// The vault, for the thumbnails a row shows. Nil until a folder is
    /// chosen, and the rows are then text only.
    let attachmentsBase: URL?
    @Binding var selection: DateKey?
    var focusRequest: Int
    let onCommand: (VimCommand) -> Bool
    let onSelectTag: (JournalTag) -> Void
    /// `e` or Return: hand the keyboard to the editor in the right-hand pane.
    let onOpenEditor: () -> Void
    /// `x`: ask for the note to go, which the window confirms first.
    let onDelete: (DateKey) -> Void

    /// The bridge to the list's own `NSTableView`, so a motion can drag the
    /// list along behind it.
    @State private var scroller = TableScroller()

    /// Where the keyboard cursor is, kept here rather than read back from
    /// `selection`.
    ///
    /// This is what makes a held `j` walk rather than take one step. The key
    /// handler is a closure built when the body was last evaluated, and SwiftUI
    /// does not re-evaluate it between the repeats of a held key: `selection`
    /// is a `Binding` whose getter captures that same stale copy, so every
    /// repeat read the position from before the first move and wrote the same
    /// destination back. `@State` is a reference into live storage — read here,
    /// it is always the row the cursor actually reached. The activity list has
    /// carried the same pair for the same reason.
    @State private var cursor: Int?
    /// The selection this cursor stands for, so a selection made elsewhere — a
    /// click, the calendar, ⌘N — is recognised as not ours and re-derived.
    @State private var cursorSelection: DateKey?

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

    /// The rows whose content changed between two lists of days.
    ///
    /// Compared position by position, since a day's row *is* its position:
    /// typing never reorders the list, and a day appearing or disappearing is
    /// an insertion the table measures for itself. When the count moves, every
    /// row from the first difference on has shifted onto other content, so they
    /// are all named — a fresh reload of the folder, not a keystroke.
    static func changedRows(from old: [JournalDay], to new: [JournalDay]) -> IndexSet {
        guard old.count == new.count else {
            let firstDifference = zip(old, new).prefix { $0 == $1 }.count
            return IndexSet(integersIn: firstDifference..<max(new.count, firstDifference))
        }
        return IndexSet(new.indices.filter { old[$0] != new[$0] })
    }

    var body: some View {
        List(days, selection: $selection) { day in
            row(day)
                .tag(day.date)
        }
        .listStyle(.inset)
        // Row heights are left alone here: a day carrying tags is taller than
        // one without, and pinning them to the first row's would clip the rest.
        .background(TableBridge(pinsRowHeight: false, scroller: scroller))
        // A row that keeps its identity keeps the height AppKit measured for
        // it, and a note being typed changes under one: see `remeasureRows`.
        .onChange(of: days) { old, new in
            scroller.remeasureRows(at: Self.changedRows(from: old, to: new))
        }
        // A selection that is not the one we wrote came from somewhere else —
        // a click, the sidebar's calendar, ⌘N — so the remembered cursor is
        // stale and the next motion re-derives it from the selection.
        .onChange(of: selection) { _, new in
            if new != cursorSelection { cursor = nil }
        }
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
                return moveTo(0)
            case .last:
                return moveTo(days.count - 1)
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
            // A day that is in the list only because an outing, a meal or a
            // weigh-in wrote something has no file to trash, and that text is
            // edited where it lives. Refused rather than swallowed, so the
            // press falls through instead of raising a dialog that would do
            // nothing.
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

    /// Moves the cursor and the selection to a row, and takes the list there.
    private func moveTo(_ index: Int) -> Bool {
        guard days.indices.contains(index) else { return false }
        let date = days[index].date
        cursor = index
        cursorSelection = date
        selection = date
        // And the list follows. Without this a held `j` walks the selection off
        // the bottom of the window: the rows keep moving, but out of sight.
        scroller.scroll(toRow: index)
        return true
    }

    private func moveSelection(by delta: Int) -> Bool {
        guard let destination = VimMotion.destination(
            from: startingPoint, delta: delta, count: days.count
        ) else { return false }
        return moveTo(destination)
    }

    /// Where the next motion starts from: the remembered cursor while it still
    /// stands for what is selected, the selection otherwise.
    private var startingPoint: Int? {
        if let cursor, days.indices.contains(cursor),
           days[cursor].date == cursorSelection {
            return cursor
        }
        return selection.flatMap { key in
            days.firstIndex { $0.date == key }
        }
    }

    private func row(_ day: JournalDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.fullDate(day.date.date()))
                        .font(.headline)
                    // Rendered, not shown raw: `__« Entre Pôtes »__` in a row
                    // is the note's typing showing through, and the reader has
                    // no use for it. The same call the pane uses to read a
                    // note, hashes dropped for the same reason there — the
                    // chips below already say the tags.
                    MarkdownText.inline(
                        day.excerpt(matching: query) ?? day.summary,
                        hidingTagHashes: true
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                // Beside the words rather than under them: a row is a day, and
                // two thumbnails at the end of its title line say there are
                // pictures without costing the list a line per row.
                JournalThumbnailStrip(
                    sources: day.note.imagePaths.map { .vault(path: $0) }
                        + day.marks.photoIDs.map { .photo(id: $0) },
                    folder: attachmentsBase
                )
            }
            if !day.tags.isEmpty || !day.marks.sports.isEmpty || day.marks.weighed {
                FlowLayout(spacing: 4) {
                    // The marks first: what the day did, then what it was
                    // filed under. A glyph is read faster than a word, and it
                    // is the one thing here that is true even of a day nobody
                    // wrote a line about.
                    ForEach(day.marks.sports) { sport in
                        Image(systemName: sport.symbolName)
                            .font(.caption)
                            .foregroundStyle(sport.color)
                            .help(sport.displayName)
                    }
                    if day.marks.weighed {
                        Image(systemName: "scalemass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Pesée ce jour-là")
                    }
                    ForEach(day.tags.sorted()) { tag in
                        JournalTagChip(tag: tag) { onSelectTag(tag) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
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
        // Clickable, never focusable. These chips sit inside the rows of a
        // `List`, and a focusable control in a row takes the keyboard from the
        // list the moment that row is selected: the first `j` moved the
        // selection onto a chip, and every repeat after it went to the chip,
        // which does nothing with a key. Held `j` looked as though it fired
        // once. The activity list has no control inside a row, which is why it
        // never had the problem.
        .focusable(false)
        .help("Ne garder que les notes portant \(tag.name)")
    }
}
