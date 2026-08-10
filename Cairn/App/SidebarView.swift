import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case all
    case globalMap
    case statistics
    case nutrition
    case weight
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

    private var sportCounts: [SportTally.Row] {
        SportTally.rows(for: activities.map(\.sportType))
    }

    /// The filter sections drive the activity screens; beside the food and
    /// weight journals they would filter nothing on screen.
    private var showsFilters: Bool {
        selection != .nutrition && selection != .weight
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
                Label("Alimentation", systemImage: "fork.knife")
                    .tag(SidebarItem.nutrition)
                Label("Poids", systemImage: "scalemass")
                    .tag(SidebarItem.weight)

                // Sits with the map rather than among the filters: it undoes a
                // rectangle drawn there, and that is where it will be looked for.
                if showsFilters, filter.region != nil {
                    Button {
                        filter.region = nil
                    } label: {
                        Label("Retirer la zone", systemImage: "xmark.circle")
                    }
                    .help("Retirer le filtre géographique dessiné sur la carte")
                }
            }

            if showsFilters {
                Section("Sports") {
                    ForEach(sportCounts) { entry in
                        Toggle(isOn: binding(for: entry.sport)) {
                            HStack {
                                SportLabel(entry.sport.displayName, sport: entry.sport)
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
                        title: "D+ min.", unit: "m", value: $filter.minElevation
                    )
                    OptionalNumberField(
                        title: "D+ max.", unit: "m", value: $filter.maxElevation
                    )
                    OptionalNumberField(
                        title: "D+/km min.", unit: "m/km",
                        value: $filter.minElevationPerKm
                    )
                }

                Section("Étiquettes") {
                    ForEach(ActivityLabel.allCases) { label in
                        Toggle(isOn: binding(for: label)) {
                            GutteredLabel(label.displayName, systemImage: label.symbolName)
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
        }
        .listStyle(.sidebar)
        // The list paints its own opaque background over anything behind it.
        // The material itself lives on the column, in `RootView.sidebar`:
        // placed here it ended up under SwiftUI's own sidebar fill and never
        // showed.
        .scrollContentBackground(.hidden)
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
