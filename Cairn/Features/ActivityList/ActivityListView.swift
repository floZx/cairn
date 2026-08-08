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

        let current = selection.count == 1
            ? rows.firstIndex { $0.id == selection.first } : nil
        guard let index = VimMotion.destination(
            from: current, delta: delta, count: rows.count
        ) else { return }
        // Replaces rather than extends: these motions move the cursor, and a
        // growing selection would turn `j` into a way to select everything.
        selection = [rows[index].id]
    }

    var body: some View {
        // Bound once: `rows` filters and sorts the whole query, and it used to be
        // recomputed for the table and again for each half of the title.
        let rows = rows
        return Table(
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
        .navigationTitle(
            rows.count == 1 ? "1 activité" : "\(rows.count) activités"
        )
        // The window subtitle, so the count is never read as the whole library
        // when it is in fact a filtered slice of it.
        .navigationSubtitle(filter.summary ?? "")
        .background(FixedTableRowHeight())
        // Motions are answered here, where the sorted rows are; everything
        // else goes to the parent, which is also what the statistics and the
        // map hand it.
        .vimKeys { command in
            perform(command, in: rows)
            return true
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
    }
}
