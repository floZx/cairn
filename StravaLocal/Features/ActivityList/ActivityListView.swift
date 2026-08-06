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
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.startLocalDate) { activity in
                Text(Format.dateOnly(activity.startLocalDate))
            }
            .width(min: 140, ideal: 160)

            TableColumn("Nom", value: \.name) { activity in
                Label(activity.name, systemImage: activity.sportType.symbolName)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Sport", value: \.sportTypeRaw) { activity in
                Text(activity.sportType.displayName)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Distance", value: \.distance) { activity in
                Text(Format.distance(activity.distance))
            }
            .width(min: 80, ideal: 90)

            TableColumn("Durée", value: \.movingTime) { activity in
                Text(Format.duration(activity.movingTime))
            }
            .width(min: 80, ideal: 90)

            TableColumn("D+", value: \.totalElevationGain) { activity in
                Text(Format.elevation(activity.totalElevationGain))
            }
            .width(min: 70, ideal: 80)

            TableColumn("D+/km", value: \.elevationPerKilometre) { activity in
                Text(Format.elevationPerKilometre(activity.elevationPerKilometre))
            }
            .width(min: 80, ideal: 90)

            TableColumn("Vitesse", value: \.averageSpeed) { activity in
                Text(Format.speed(activity.averageSpeed, sport: activity.sportType))
            }
            .width(min: 90, ideal: 100)
        }
        .navigationTitle(
            rows.count == 1 ? "1 activité" : "\(rows.count) activités"
        )
    }
}
