import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case all
    case globalMap
    case statistics
}

/// Navigation and every filter in one pane.
///
/// Sport used to be a sidebar *selection* while the other criteria lived in a
/// bar above the list, which split one job across two places and let the
/// sidebar hold only one sport at a time. Here sport is a filter like the
/// others, so several can be combined — `ActivityFilter.sports` was already a
/// `Set`, the old UI just couldn't express it.
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Binding var filter: ActivityFilter
    @Query private var activities: [Activity]

    private var sportCounts: [(sport: SportType, count: Int)] {
        Dictionary(grouping: activities, by: \.sportType)
            .map { (sport: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Mes activités", systemImage: "list.bullet")
                    .badge(activities.count)
                    .tag(SidebarItem.all)
                Label("Carte globale", systemImage: "map")
                    .tag(SidebarItem.globalMap)
                Label("Statistiques", systemImage: "chart.bar")
                    .tag(SidebarItem.statistics)

                // Sits with the map rather than among the filters: it undoes a
                // rectangle drawn there, and that is where it will be looked for.
                if filter.region != nil {
                    Button {
                        filter.region = nil
                    } label: {
                        Label("Retirer la zone", systemImage: "xmark.circle")
                    }
                    .help("Retirer le filtre géographique dessiné sur la carte")
                }
            }

            Section("Sports") {
                ForEach(sportCounts, id: \.sport) { entry in
                    Toggle(isOn: binding(for: entry.sport)) {
                        HStack {
                            Label(entry.sport.displayName, systemImage: entry.sport.symbolName)
                            Spacer(minLength: 8)
                            Text("\(entry.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Section("Filtres") {
                Picker("Période", selection: $filter.period) {
                    ForEach(DatePeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                OptionalNumberField(
                    title: "Distance min.", unit: "km", value: $filter.minDistanceKm
                )
                OptionalNumberField(
                    title: "Distance max.", unit: "km", value: $filter.maxDistanceKm
                )
                OptionalNumberField(
                    title: "Durée min.", unit: "min", value: $filter.minDurationMinutes
                )
                OptionalNumberField(
                    title: "D+ min.", unit: "m", value: $filter.minElevation
                )
                OptionalNumberField(
                    title: "D+/km min.", unit: "m/km",
                    value: $filter.minElevationPerKm
                )
            }

            Section("Étiquettes") {
                ForEach(ActivityLabel.allCases) { label in
                    Toggle(isOn: binding(for: label)) {
                        Label(label.displayName, systemImage: label.symbolName)
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if filter.isActive {
                Section {
                    // The count is on the button because that is where the eye
                    // already goes to undo a filter; the window subtitle says
                    // which ones.
                    Button("Réinitialiser les filtres (\(filter.activeCriteriaCount))") {
                        filter = .none
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func binding(for label: ActivityLabel) -> Binding<Bool> {
        Binding(
            get: { filter.labels.contains(label) },
            set: { isOn in
                if isOn {
                    filter.labels.insert(label)
                } else {
                    filter.labels.remove(label)
                }
            }
        )
    }

    /// No sport checked means no sport filter at all, so the empty set has to
    /// behave as "everything" rather than "nothing".
    private func binding(for sport: SportType) -> Binding<Bool> {
        Binding(
            get: { filter.sports.contains(sport) },
            set: { isOn in
                if isOn {
                    filter.sports.insert(sport)
                } else {
                    filter.sports.remove(sport)
                }
            }
        )
    }
}
