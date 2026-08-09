import SwiftUI
import SwiftData

struct ActivityListView: View {
    let filter: ActivityFilter
    // `Activity.ID` (the macro-synthesized `PersistentModel` typealias) isn't
    // nameable via dot-syntax outside the file that declares `Activity`, even
    // within the same module — a known SwiftData/macro limitation. It aliases
    // to `PersistentIdentifier`, which is used directly here instead.
    /// A set, so several activities can be compared on one map. One selection
    /// still opens the usual detail pane.
    @Binding var selection: Set<PersistentIdentifier>

    /// Owned by the parent so it survives this view's `.id(filter)`: the first
    /// row is picked once per launch, not again every time a filter changes and
    /// re-instantiates the list under the user.
    @Binding var hasAutoSelected: Bool

    /// Commands this view cannot carry out itself — changing section, editing,
    /// deleting. Motions stay here, where the sorted rows are.
    let onCommand: (VimCommand) -> Void

    /// Built in `init` from the incoming filter. The parent applies
    /// `.id(filter)` so a filter change re-instantiates the view, which is what
    /// rebuilds this query — `@Query` can't be mutated in place.
    @Query private var query: [Activity]

    @State private var sortOrder = [
        KeyPathComparator(\Activity.startDate, order: .reverse)
    ]

    /// Which presentation is showing. Persisted: it is a preference, not a mode
    /// — someone who prefers cards prefers them tomorrow too.
    @AppStorage(ActivityListStyle.storageKey)
    private var style: ActivityListStyle = .table

    /// Set by the probe below, used to follow the keyboard cursor.
    @State private var scroller = TableScroller()

    /// Where the keyboard cursor is, and what it last wrote to the selection.
    ///
    /// Deriving the starting point from `selection` on every motion looks right
    /// and is right at typing speed, but a held key fires sixty times a second
    /// and a `@Binding` write is not visible to the next read in the same
    /// runloop pass. Every repeat therefore started from the *same* row and
    /// landed on the same one — the key repeated and nothing moved.
    @State private var cursor: Int?
    @State private var cursorSelection: Set<PersistentIdentifier> = []

    /// Bumped whenever the keyboard should come back to the list.
    @State private var focusRequest = 0

    /// Which columns are shown, in which order, at which width — right-click the
    /// header to choose, drag to reorder, exactly as in the Finder. Persisted in
    /// `AppStorage` rather than `SceneStorage` so it survives a relaunch and not
    /// merely a window restore.
    ///
    /// The key carries a version because a stored order overrides the declared
    /// one: moving a column in code would otherwise have no effect for anyone
    /// who had already used the table. Bump it when the default order changes.
    @AppStorage("activityColumns.v2")
    private var columnCustomization = TableColumnCustomization<Activity>()

    init(
        filter: ActivityFilter,
        selection: Binding<Set<PersistentIdentifier>>,
        hasAutoSelected: Binding<Bool>,
        onCommand: @escaping (VimCommand) -> Void
    ) {
        self.filter = filter
        self._selection = selection
        self._hasAutoSelected = hasAutoSelected
        self.onCommand = onCommand
        _query = Query(
            filter: filter.predicate(),
            sort: [SortDescriptor(\Activity.startDate, order: .reverse)]
        )
    }

    private var rows: [Activity] {
        query.filter(filter.matchesPrecisely).sorted(using: sortOrder)
    }

    /// The row to select when the list first appears, or nil to leave the
    /// selection alone.
    ///
    /// Only ever the newest activity, and only when the user has chosen nothing:
    /// opening on an empty pane wastes the window, but overriding a selection the
    /// user made — or made a point of clearing — would be worse.
    static func initialSelection(
        rows: [Activity], current: Set<PersistentIdentifier>, hasAutoSelected: Bool
    ) -> PersistentIdentifier? {
        guard !hasAutoSelected, current.isEmpty else { return nil }
        return rows.first?.id
    }

    /// Runs a motion here, hands anything else to the parent.
    private func perform(_ command: VimCommand, in rows: [Activity]) {
        let delta: Int
        switch command {
        case let .move(value): delta = value
        case let .halfPage(down):
            delta = down ? VimMotion.halfPageRows : -VimMotion.halfPageRows
        case .first: delta = -rows.count
        case .last: delta = rows.count
        default:
            onCommand(command)
            return
        }

        guard let index = VimMotion.destination(
            from: startingPoint(in: rows), delta: delta, count: rows.count
        ) else { return }

        // Replaces rather than extends: these motions move the cursor, and a
        // growing selection would turn `j` into a way to select everything.
        cursor = index
        cursorSelection = [rows[index].id]
        selection = cursorSelection
        // And the list follows. Without this the cursor walks off the bottom of
        // the window and the list stops being navigable at the very moment it is
        // being navigated.
        scroller.scroll(toRow: index)
    }

    /// Where the next motion starts from.
    ///
    /// The remembered cursor when it is still true, the selection otherwise.
    /// Trusting the cursor is what makes a held key move more than one row; the
    /// two checks are what stop it lying after the list has changed underneath.
    private func startingPoint(in rows: [Activity]) -> Int? {
        if let cursor, cursor < rows.count, cursorSelection.contains(rows[cursor].id) {
            return cursor
        }
        return selection.count == 1 ? rows.firstIndex { $0.id == selection.first } : nil
    }

    var body: some View {
        // Bound once: `rows` filters and sorts the whole query, and it used to be
        // recomputed for the table and again for each half of the title.
        let rows = rows
        return Group {
            if style == .cards {
                cards(rows)
            } else {
                table(rows)
            }
        }
        .navigationTitle(
            rows.count == 1 ? "1 activité" : "\(rows.count) activités"
        )
        // The window subtitle, so the count is never read as the whole library
        // when it is in fact a filtered slice of it.
        .navigationSubtitle(filter.summary ?? "")
        // Both presentations are backed by an `NSTableView`, and both would
        // otherwise pay for automatic row heights. See the probe's own note.
        // Keyed on the presentation: switching builds a different table, and a
        // probe that ran once would go on holding the destroyed one.
        .background(FixedTableRowHeight(scroller: scroller).id(style))
        // Clicking the selected row again clears it — the detail pane closes
        // and the list gets the width back, without reaching for ⌥⌘I.
        .background(DeselectOnRepeatClick {
            selection = []
            // The keyboard cursor went with it: leaving it behind meant the
            // next `j` resumed from a row nothing on screen pointed at.
            cursor = nil
            cursorSelection = []
        })
        // Motions are answered here, where the sorted rows are; everything
        // else goes to the parent, which is also what the statistics and the
        // map hand it.
        .vimKeys(focusRequest: focusRequest) { command in
            perform(command, in: rows)
            return true
        }
        // Switching presentation destroys the table the keyboard was in, and
        // focus goes nowhere. Both halves are asked back: SwiftUI's focus, which
        // is what feeds `onKeyPress`, and AppKit's first responder, which is what
        // draws the selected row as active.
        .onChange(of: style) { _, _ in
            focusRequest += 1
            scroller.focusWhenAttached()
        }
        // A selection that is not the one we wrote came from somewhere else — a
        // click in the list, a record in the statistics, a track on the map — so
        // the remembered cursor is stale and the next motion re-derives it.
        .onChange(of: selection) { _, new in
            if new != cursorSelection { cursor = nil }
        }
        .onAppear {
            if let first = Self.initialSelection(
                rows: rows, current: selection, hasAutoSelected: hasAutoSelected
            ) {
                selection = [first]
            }
            // Set even when nothing was selected — an empty library on first
            // launch must not arm the auto-selection for the next filter change.
            hasAutoSelected = true
        }
        .toolbar {
            // Only with the cards: the table sorts by clicking a header, and a
            // second control for the same thing would be one too many.
            if style == .cards {
                ToolbarItem { sortMenu }
            }
            ToolbarItem {
                Picker("Présentation", selection: $style) {
                    ForEach(ActivityListStyle.allCases) { option in
                        Label(option.displayName, systemImage: option.symbolName)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Basculer entre le tableau et les fiches")
            }
        }
    }

    /// Writes into the same `sortOrder` the table's headers drive, so switching
    /// presentation never reshuffles what is on screen.
    private var sortMenu: some View {
        Menu {
            ForEach(ActivitySort.allCases) { option in
                Button {
                    // Same field tapped twice reverses it, as a column header
                    // does — the one gesture everyone already knows.
                    sortOrder = option.comparators(
                        ascending: ActivitySort.current(sortOrder) == option
                            ? !ActivitySort.isAscending(sortOrder)
                            : option.startsAscending
                    )
                } label: {
                    if ActivitySort.current(sortOrder) == option {
                        Label(
                            option.displayName,
                            systemImage: ActivitySort.isAscending(sortOrder)
                                ? "chevron.up" : "chevron.down"
                        )
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Label("Trier", systemImage: "arrow.up.arrow.down")
        }
        .help("Trier les fiches")
    }

    /// The rich presentation: one card per activity.
    private func cards(_ rows: [Activity]) -> some View {
        List(rows, selection: $selection) { activity in
            ActivityCard(activity: activity)
                .listRowInsets(ActivityCard.rowInsets)
                .tag(activity.id)
        }
        .listStyle(.inset)
        // The height SwiftUI assumes for rows it has not built yet. Its
        // default assumption is 24 pt under 50 pt cards, and a fast scroll
        // into unbuilt territory laid rows out at that estimate — cards drawn
        // over each other until a correction pass. With the estimate equal to
        // the real height there is nothing to correct, ever. (AppKit-level
        // row-height pinning cannot fix this list: SwiftUI's delegate serves
        // the heights — verified live, `usesAutomaticRowHeights` already
        // false, estimated rows answering 24.)
        .environment(\.defaultMinListRowHeight, ActivityCard.rowHeight)
    }

    private func table(_ rows: [Activity]) -> some View {
        Table(
            rows,
            selection: $selection,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("Date", value: \.startLocalDate) { activity in
                Text(Format.dateOnly(activity.startLocalDate))
            }
            // "12 déc. 2025" is the widest this gets, now the time is gone.
            .width(min: 90, ideal: 105)
            .customizationID("date")

            // No `customizationID`, which is what makes this column permanent:
            // it carries the sport icon, so hiding it would leave rows
            // unreadable. It stays second unless the date is hidden.
            TableColumn("Nom", value: \.name) { activity in
                SportLabel(activity.name, sport: activity.sportType)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Distance", value: \.distance) { activity in
                Text(Format.distance(activity.distance))
            }
            .width(min: 80, ideal: 90)
            .customizationID("distance")

            TableColumn("Durée", value: \.movingTime) { activity in
                Text(Format.durationCompact(activity.movingTime))
            }
            .width(min: 80, ideal: 90)
            .customizationID("duration")

            TableColumn("D+", value: \.totalElevationGain) { activity in
                Text(Format.elevation(activity.totalElevationGain))
            }
            .width(min: 70, ideal: 80)
            .customizationID("elevation")

            TableColumn("D+/km", value: \.elevationPerKilometre) { activity in
                Text(Format.elevationPerKilometre(activity.elevationPerKilometre))
            }
            .width(min: 80, ideal: 90)
            .customizationID("elevationPerKilometre")

            TableColumn("Vitesse", value: \.averageSpeed) { activity in
                Text(Format.speed(activity.averageSpeed, sport: activity.sportType))
            }
            .width(min: 90, ideal: 100)
            .customizationID("speed")

            TableColumn("FC moy.", value: \.averageHeartrateOrZero) { activity in
                Text(Format.heartrate(activity.averageHeartrate))
            }
            .width(min: 80, ideal: 90)
            .customizationID("averageHeartRate")

            TableColumn("Étiquettes") { activity in
                HStack(spacing: 4) {
                    ForEach(activity.labels) { label in
                        Image(systemName: label.symbolName)
                            .foregroundStyle(.secondary)
                    }
                }
                .help(activity.labels.map(\.displayName).joined(separator: ", "))
            }
            .width(min: 60, ideal: 80)
            .customizationID("labels")
        }
    }
}
