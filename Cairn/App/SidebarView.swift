import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case all
    case globalMap
    case statistics
    case journal
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
    /// The ticked tags, when the journal is showing. Held by `RootView` like
    /// every other filter, so the list and this pane never disagree.
    @Binding var journalTags: Set<JournalTag>
    @Environment(AppEnvironment.self) private var app
    @Query private var activities: [Activity]

    private var sportCounts: [SportTally.Row] {
        SportTally.rows(for: activities.map(\.sportType))
    }

    private var tagCounts: [JournalTagTally.Row] {
        JournalTagTally.rows(for: app.journal.notes.map(\.tags))
    }

    /// The filter sections belong to the activity screens; beside the journal,
    /// the food and weight screens they would filter nothing on screen.
    ///
    /// A deselected sidebar is still one of the activity screens: the content
    /// column falls through to the list when nothing is selected, and the
    /// filters have to be there with it. Hence a whitelist that reads nil as
    /// the list it actually shows, rather than one that only names sections.
    private var showsFilters: Bool {
        selection == nil || selection == .all || selection == .globalMap
            || selection == .statistics
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
                Label("Journal", systemImage: "text.book.closed")
                    .badge(app.journal.notes.count)
                    .tag(SidebarItem.journal)
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

            if selection == .journal {
                if !tagCounts.isEmpty {
                    Section("Tags") {
                        ForEach(tagCounts) { entry in
                            Toggle(isOn: binding(for: entry.tag)) {
                                HStack {
                                    Text(entry.tag.displayName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text("\(entry.count)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                // Outside the section above, and deliberately: point the
                // journal at a folder whose notes carry none of the ticked
                // tags and there are no counts to list, while the ticks are
                // still filtering the list down to nothing. Nested, the one
                // button that undoes them went with the tags.
                if !journalTags.isEmpty {
                    Section {
                        Button("Retirer les tags (\(journalTags.count))") {
                            journalTags = []
                        }
                    }
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

    /// Ticked tags narrow rather than widen: a note carries several, so the
    /// point of ticking a second one is to combine them. Sports work the other
    /// way round because an activity has exactly one — see `JournalNote.has`.
    private func binding(for tag: JournalTag) -> Binding<Bool> {
        Binding(
            get: { journalTags.contains(tag) },
            set: { isOn in
                if isOn {
                    journalTags.insert(tag)
                } else {
                    journalTags.remove(tag)
                }
            }
        )
    }
}
