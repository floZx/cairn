import SwiftUI
import SwiftData

struct ActivityListView: View {
    let filter: ActivityFilter
    // `Activity.ID` (the macro-synthesized `PersistentModel` typealias) isn't
    // nameable via dot-syntax outside the file that declares `Activity`, even
    // within the same module — a known SwiftData/macro limitation. It aliases
    // to `PersistentIdentifier`, which is used directly here instead.
    @Binding var selection: PersistentIdentifier?

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

    init(filter: ActivityFilter, selection: Binding<PersistentIdentifier?>) {
        self.filter = filter
        self._selection = selection
        _query = Query(
            filter: filter.predicate(),
            sort: [SortDescriptor(\Activity.startDate, order: .reverse)]
        )
    }

    private var rows: [Activity] {
        query.filter(filter.matchesPrecisely).sorted(using: sortOrder)
    }

    var body: some View {
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
                Label(activity.name, systemImage: activity.sportType.symbolName)
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
                Text(Format.heartRate(activity.averageHeartrate))
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
    }
}
