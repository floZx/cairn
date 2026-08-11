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

    /// Every day the journal lists — for the badge, and for the calendar's
    /// dots, which must mark a day written about in an outing's note just as
    /// they mark one with a file in the vault.
    let journalDays: [JournalDay]

    /// The tags to tick, with their counts. Computed by `RootView`, which is
    /// where the vault's notes and the outings' notes are already merged —
    /// counting them again here would mean merging them twice.
    let journalTagCounts: [JournalTagTally.Row]

    /// The day the calendar shows as chosen, and opens when one is clicked.
    ///
    /// A plain `DateKey` rather than the optional selection: the calendar has
    /// to mark *some* month even when nothing is open. `RootView` maps it onto
    /// `journalSelection` and onto the store — see `journalDayBinding`.
    @Binding var journalDay: DateKey

    /// The food journal's day, for its own calendar. The same binding the
    /// journal screen travels on, so the two never disagree.
    @Binding var nutritionDay: DateKey

    /// A calendar is a grid, not a row: on the list's own row insets it loses
    /// a column to them.
    private static let calendarInsets = EdgeInsets(
        top: 4, leading: 6, bottom: 4, trailing: 6
    )
    @Environment(AppEnvironment.self) private var app
    @Query private var activities: [Activity]

    private var sportCounts: [SportTally.Row] {
        SportTally.rows(for: activities.map(\.sportType))
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
                    .badge(journalDays.count)
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

            // Both day-keyed sections put their calendar here, in the one pane
            // that is on screen whatever the content column is showing. The
            // food journal's used to sit in the right-hand panel, which is the
            // side one reads results on, not the side one navigates from.
            if selection == .nutrition {
                Section {
                    NutritionCalendarSection(selected: $nutritionDay)
                        .listRowInsets(Self.calendarInsets)
                }
            }

            if selection == .journal {
                // Above the tags, because it answers the question one arrives
                // with — "what did I write on the 6th?" — where the tags answer
                // the one that comes after, "what have I written about Sam?".
                Section {
                    MiniCalendarView(
                        selected: $journalDay,
                        loggedDays: Set(journalDays.map(\.date.raw))
                    )
                    .listRowInsets(Self.calendarInsets)
                }

                if !journalTagCounts.isEmpty {
                    Section("Tags") {
                        ForEach(journalTagCounts) { entry in
                            Toggle(isOn: binding(for: entry.tag)) {
                                HStack {
                                    // The bare name, not `displayName`: the
                                    // section is already titled "Tags", so the
                                    // `#` says nothing here that the header has
                                    // not said once for the whole list. It
                                    // stays on the chips, where a tag sits in
                                    // running text with nothing to announce it.
                                    Text(entry.tag.name)
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
