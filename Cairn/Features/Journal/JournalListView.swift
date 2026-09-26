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
    /// Where the thumbnails a row shows resolve to: the attachment cache,
    /// which always exists. `loadError` stood beside it while a folder could
    /// go missing under the journal; nothing can now, so an empty list means
    /// an empty journal and nothing else.
    let attachmentsBase: URL
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
    /// are all named — a list rebuilt from the base, not a keystroke.
    static func changedRows(from old: [JournalDay], to new: [JournalDay]) -> IndexSet {
        guard old.count == new.count else {
            let firstDifference = zip(old, new).prefix { $0 == $1 }.count
            return IndexSet(integersIn: firstDifference..<max(new.count, firstDifference))
        }
        return IndexSet(new.indices.filter { old[$0] != new[$0] })
    }

    var body: some View {
        // Le mois une fois, dans un en-tête collant, et plus dans chaque
        // ligne : la date longue en gras, identique d'une ligne à l'autre,
        // prenait le poids qui revient à ce qui est écrit.
        List(selection: $selection) {
            ForEach(JournalRowLayout.months(of: days)) { month in
                Section {
                    ForEach(month.days) { day in
                        row(day)
                            .tag(day.date)
                    }
                } header: {
                    Text(month.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        // Counted like the activities' « 893 activités »: the window said
        // « Cairn » here, and the sidebar's number had nothing to say what it
        // counted.
        .navigationTitle(days.count == 1 ? "1 journée" : "\(days.count) journées")
        // Row heights are left alone here: a day carrying tags is taller than
        // one without, and pinning them to the first row's would clip the rest.
        .background(TableBridge(pinsRowHeight: false, scroller: scroller))
        // A row that keeps its identity keeps the height AppKit measured for
        // it, and a note being typed changes under one: see `remeasureRows`.
        .onChange(of: days) { old, new in
            // Toujours une journée ouverte : celle qui l'était a pu disparaître
            // de la liste — sa note supprimée, une recherche ou une étiquette
            // qui l'écarte — et le volet se refermait sur rien.
            if let current = selection, !new.contains(where: { $0.date == current }) {
                // Sa voisine, là où elle était, plutôt que le haut de la liste.
                let place = old.firstIndex { $0.date == current } ?? 0
                selection = new.isEmpty ? nil : new[min(place, new.count - 1)].date
            } else if selection == nil, let first = new.first {
                selection = first.date
            }
            // In the table's rows, which count the month headers too.
            scroller.remeasureRows(
                at: JournalRowLayout.tableRows(
                    forDays: Self.changedRows(from: old, to: new), in: new
                )
            )
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
        .onAppear {
            if let first = Self.initialSelection(days: days, current: selection) {
                selection = first
            }
        }
        .overlay {
            if days.isEmpty {
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
            // Same for `x`: the thing this screen can delete is the day's own
            // note. A day that is in the list only because an outing, a meal
            // or a weigh-in wrote something has none of its own, and that text
            // is edited where it lives. Refused rather than swallowed, so the
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
        scroller.scroll(toRow: JournalRowLayout.tableRow(forDay: index, in: days))
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

    /// The weigh-in's glyph, only while the weight has a screen of its own:
    /// hidden since 24 September, it left a scale on rows that led nowhere.
    private func showsWeighIn(_ day: JournalDay) -> Bool {
        day.marks.weighed && !SidebarItem.weight.estMasquee
    }

    private func row(_ day: JournalDay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            JournalDateTile(date: day.date)
            prose(day)
                // The separator starts after the tile, not at the edge: the
                // tile is the row's anchor, as the round badge is in the
                // activity list.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 8)
            side(day)
        }
        .frame(minHeight: 50, alignment: .top)
        .padding(.vertical, 8)
    }

    /// One paragraph, three lines at most: the first sentence in the text's
    /// colour, the rest after it in secondary on the same run — two blocks
    /// would leave a hole under a note that is a single sentence. Rendered
    /// rather than raw, mentions in the accent colour as everywhere.
    private func prose(_ day: JournalDay) -> some View {
        let preview = JournalRowLayout.preview(of: day, matching: query)
        let lead = MarkdownText.inline(preview.lead, hidingTagHashes: true)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
        let rest = MarkdownText.inline(preview.rest, hidingTagHashes: true)
            .foregroundStyle(.secondary)
        return Text("\(lead) \(rest)")
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the day did and what it is filed under, top right; its pictures
    /// under them.
    private func side(_ day: JournalDay) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(day.tags.sorted()) { tag in
                    JournalTagChip(tag: tag) { onSelectTag(tag) }
                }
                ForEach(day.marks.sports) { sport in
                    SportDot(sport: sport, size: 16)
                }
                if showsWeighIn(day) {
                    Image(systemName: "scalemass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Pesée ce jour-là")
                }
            }
            JournalThumbnailStrip(
                sources: day.note.imagePaths.map { .vault(path: $0) }
                    + day.marks.photoIDs.map { .photo(id: $0) },
                folder: attachmentsBase
            )
        }
        .padding(.top, 2)
    }
}

/// The day's anchor at the left of a row: « SAM » over « 26 », in the accent
/// colour for today — what the round badge is to the activity list.
struct JournalDateTile: View {
    let date: DateKey

    var body: some View {
        let tile = JournalRowLayout.tile(for: date)
        let isToday = date == DateKey(Date())
        // Les dimanches en rouge, comme dans un agenda de papier : la semaine
        // se découpe d'un coup d'œil. Aujourd'hui garde la couleur d'accent,
        // même un dimanche.
        let isSunday = Calendar(identifier: .gregorian).component(.weekday, from: date.date()) == 1
        let weekdayStyle: AnyShapeStyle = isToday
            ? AnyShapeStyle(.tint) : isSunday ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
        let dayStyle: AnyShapeStyle = isToday
            ? AnyShapeStyle(.tint) : isSunday ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
        VStack(spacing: 0) {
            Text(tile.weekday)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(weekdayStyle)
            Text(tile.day)
                .font(.system(size: 21, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(dayStyle)
        }
        .frame(width: 38)
        .padding(.top, 1)
    }
}

/// A sport as a small coloured disc with its glyph in white — the activity
/// list's colours, at the size of a mark.
struct SportDot: View {
    let sport: SportType
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: sport.symbolName)
            .font(.system(size: size * 0.58, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(sport.color, in: .circle)
            .help(sport.displayName)
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
