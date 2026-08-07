import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modelContext) private var modelContext
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var filter = ActivityFilter.none
    // See the comment on `ActivityListView.selection`: `Activity.ID` can't be
    // named from this file, so `PersistentIdentifier` is used directly.
    @State private var selectedActivities: Set<PersistentIdentifier> = []
    /// Which map, if any, is filling the window.
    @State private var expandedMap: ExpandedMap?
    /// Which editor is open, if any. One state rather than two booleans: the two
    /// modes are exclusive and a pair of flags would let both be true.
    @State private var editor: ActivityEditorSheet.Mode?
    /// The activity a confirmation dialog is about to delete. Introduced here
    /// for the toolbar's Supprimer button; the confirmation itself is task 7's.
    @State private var pendingDeletion: Activity?
    /// Set when a write the user believes already happened — a delete, a
    /// restore, a save from the editor sheet — actually failed. Both `delete`
    /// and the editor's `onSave` change what is on screen (the selection
    /// clears, the sheet dismisses) before `try?` used to hide a failed
    /// `context.save()` behind a screen that already looks correct.
    @State private var writeFailureMessage: String?
    /// Shared with every map so the chosen background and colour carry over.
    @AppStorage(MapStyle.storageKey) private var expandedStyle: MapStyle = .standard
    @AppStorage(TrackColor.storageKey) private var expandedTrackColor: TrackColor = .accent
    @Query private var allActivities: [Activity]

    /// The selected activities, restricted to those the list actually shows.
    ///
    /// Resolved against the filtered set rather than the whole library: a filter
    /// can hide a selected activity, and a detail pane for a row that is no
    /// longer in the list is a pane the list offers no way to close. The stored
    /// ids are deliberately left alone, so lifting the filter brings the
    /// selection back rather than silently discarding it.
    private var selection: [Activity] {
        guard !selectedActivities.isEmpty else { return [] }
        return mapActivities.filter { selectedActivities.contains($0.id) }
    }

    /// The one selected activity, or nil as soon as there are several: the
    /// detail pane shows figures for one outing and a comparison map for more.
    private var selected: Activity? {
        selection.count == 1 ? selection.first : nil
    }

    /// The global map honours the same filters as the list — picking a sport in
    /// the sidebar or typing a search has to narrow the tracks too, otherwise
    /// the map contradicts every other view.
    private var mapActivities: [Activity] {
        filter.apply(to: allActivities)
    }

    /// Everything the filters keep except the date range, which the statistics
    /// view sets for itself — it has to reach into the preceding period to
    /// compare against it.
    private var statisticsActivities: [Activity] {
        filter.ignoringPeriod.apply(to: allActivities)
    }

    var body: some View {
        // The sheet, the deletion dialog, and the menu bridge below live on
        // this outer `Group` rather than on `splitView`: an empty library
        // shows `WelcomeView` instead, and a modifier attached only to the
        // branch that never renders yet never fires — `app.requestNewActivity`
        // stayed nil and ⌘N stayed disabled for exactly the person with no
        // Strava account, the one this journal is supposed to work for first.
        Group {
            if let expandedMap {
                fullWindowMap(expandedMap)
            } else if allActivities.isEmpty && !app.progress.isRunning {
                WelcomeView()
                    .frame(minWidth: 900, minHeight: 600)
            } else {
                splitView
            }
        }
        .sheet(item: $editor) { mode in
            ActivityEditorSheet(mode: mode) { draft in
                // `Mode.apply` carries the switch that used to live here; kept
                // out of this closure so a test can reach it directly.
                let activity = mode.apply(draft)
                if case .create = mode {
                    modelContext.insert(activity)
                    selectedActivities = [activity.id]
                }
                do {
                    try modelContext.save()
                } catch {
                    // `apply` already mutated the object in memory: the screen
                    // shows the edit whether or not this succeeds, so silence
                    // here would be the worst kind — the user believes their
                    // work is saved.
                    writeFailureMessage =
                        "Votre modification n'a pas pu être enregistrée. \(error.localizedDescription)"
                }
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Supprimer « \($0.name) » ?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let pendingDeletion {
                    delete(pendingDeletion)
                }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            // `ActivitySource.deleteConfirmationMessage` carries the branch
            // that used to live here, tested on its own: see its doc comment
            // for why the two sources cannot share one text.
            Text(pendingDeletion?.source.deleteConfirmationMessage ?? "")
        }
        .alert(
            "Échec de l'enregistrement",
            isPresented: Binding(
                get: { writeFailureMessage != nil },
                set: { if !$0 { writeFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { writeFailureMessage = nil }
        } message: {
            Text(writeFailureMessage ?? "")
        }
        .onAppear {
            app.requestNewActivity = { editor = .create }
            app.requestEditSelection = { if let selected { editor = .edit(selected) } }
            app.requestDeleteSelection = { pendingDeletion = selected }
        }
    }

    /// A map on its own, with the sidebar and the detail pane out of the way.
    @ViewBuilder
    private func fullWindowMap(_ expanded: ExpandedMap) -> some View {
        let map = Group {
            switch expanded {
            case .global:
                GlobalMapView(
                    activities: mapActivities,
                    region: regionBinding,
                    // Clicking a track leaves the full-window map for the pane
                    // that can actually show the activity.
                    onSelect: { id in
                        selectedActivities = [id]
                        expandedMap = nil
                    }
                )
            case .comparison:
                // Guarded because a selection can shrink under an expanded map:
                // one activity is a detail pane's business, not this map's.
                if selection.count > 1 {
                    ComparisonMapView(activities: selection)
                }
            case let .activity(id):
                if let activity = allActivities.first(where: { $0.id == id }) {
                    ActivityMapView(
                        coordinates: activity.displayCoordinates,
                        style: expandedStyle,
                        trackColor: expandedTrackColor
                    )
                    .mapChrome(style: $expandedStyle)
                }
            }
        }

        map
            .frame(minWidth: 900, minHeight: 600)
            .overlay(alignment: .topLeading) {
                Button {
                    expandedMap = nil
                } label: {
                    Label(
                        "Réduire",
                        systemImage: "arrow.down.right.and.arrow.up.left"
                    )
                }
                .buttonStyle(.plain)
                .mapControl()
                // Attached to the button, not to the view: `onExitCommand` only
                // fires for the focused view, and the map takes focus.
                .keyboardShortcut(.escape, modifiers: [])
                .help("Revenir à la liste — ou appuyez sur Échap")
                .padding()
            }
    }

    private var regionBinding: Binding<BoundingBox?> {
        Binding(
            get: { filter.region },
            set: { newRegion in
                filter.region = newRegion
                if newRegion != nil {
                    sidebarSelection = .all
                    // A region chosen from the expanded map has to reveal the
                    // list it just filtered.
                    expandedMap = nil
                }
            }
        )
    }

    private var showsGlobalMap: Bool { sidebarSelection == .globalMap }

    private var showsStatistics: Bool { sidebarSelection == .statistics }

    /// One three-column split view for the whole app life, never two.
    ///
    /// An earlier version swapped between a two- and a three-column
    /// `NavigationSplitView` so the map could span the detail pane. That reset
    /// every column width on each switch: macOS restores widths per split-view
    /// identity, and changing the column count is a different identity. The
    /// structure is now fixed, and the map claims the space by collapsing the
    /// detail column instead.
    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } content: {
            // A plain frame rather than `navigationSplitViewColumnWidth`: that
            // modifier's ideal width applies whenever the column is first
            // shown, and swapping list for map may well count as that — which
            // would silently reset the width the user dragged.
            Group {
                if showsGlobalMap {
                    GlobalMapView(
                        activities: mapActivities,
                        region: regionBinding,
                        onExpand: { expandedMap = .global },
                        onSelect: { selectedActivities = [$0] }
                    )
                } else if showsStatistics {
                    StatisticsView(activities: statisticsActivities)
                } else {
                    ActivityListView(filter: filter, selection: $selectedActivities)
                        .id(filter)
                        .searchable(
                            text: $filter.searchText,
                            prompt: "Rechercher une activité"
                        )
                }
            }
            .frame(minWidth: 480)
        } detail: {
            detailColumn
        }
        // Makes the list absorb a sidebar toggle instead of the detail pane.
        .background(SplitViewHoldingPriorities())
        .toolbar { syncToolbar }
    }

    /// Removes an activity from the journal: from the current selection so the
    /// detail pane never keeps a live reference to a deleted object, then from
    /// the store — leaving a tombstone behind when it came from Strava.
    private func delete(_ activity: Activity) {
        selectedActivities.remove(activity.id)
        // The selection is cleared above, before the write is attempted: a
        // failure here would otherwise leave the activity in place but
        // deselected, with nothing on screen to say the deletion did not
        // actually happen.
        do {
            try ImportMapper(context: modelContext).discard(activity)
        } catch {
            writeFailureMessage =
                "Votre suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    /// A floor for the detail pane whenever it actually has something to show.
    ///
    /// Not decoration: the collapse below sets the column's width to zero, and
    /// AppKit hands a reopening column back the width it had — near nothing. With
    /// no remembered width to fall back on, as after a fresh build, the pane
    /// reopened a few points wide, its labels wrapped one letter per line.
    private static let detailMinWidth: CGFloat = 360

    @ViewBuilder
    private var detailColumn: some View {
        // The global map no longer collapses the pane outright: clicking a track
        // there opens it, and the map simply gives the width back. Statistics has
        // nothing to put beside it either way.
        if showsStatistics {
            collapsedDetailColumn
        } else if let selected {
            ActivityDetailView(
                activity: selected,
                onExpandMap: { expandedMap = .activity(selected.id) }
            )
            .frame(minWidth: Self.detailMinWidth)
        } else if selection.count > 1 {
            ComparisonMapView(
                activities: selection,
                onExpand: { expandedMap = .comparison }
            )
            .frame(minWidth: Self.detailMinWidth)
        } else {
            collapsedDetailColumn
        }
    }

    /// Nothing worth a pane: beside a full-width view, or with nothing selected.
    ///
    /// Squeezing the column shut gives the width back to the list, and doing it
    /// this way keeps the split view's identity — and therefore the widths the
    /// user chose.
    private var collapsedDetailColumn: some View {
        Color.clear.navigationSplitViewColumnWidth(0)
    }

    private var sidebar: some View {
        SidebarView(selection: $sidebarSelection, filter: $filter)
            .frame(minWidth: 260)
    }

    @ToolbarContentBuilder
    private var syncToolbar: some ToolbarContent {
            ToolbarItem(placement: .status) {
                if app.progress.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(app.progress.toolbarText)
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            // Reserved on the text alone, so the pill keeps a
                            // steady width as the counter ticks over without
                            // pinning its contents against one edge.
                            .frame(width: 96, alignment: .leading)
                    }
                    .help(app.progress.statusText)
                }
            }
            ToolbarItem {
                Button {
                    app.syncNow()
                } label: {
                    Label("Synchroniser", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!app.isAuthenticated || app.progress.isRunning)
                // Already worded for every phase: the last run's date and time
                // when idle, "Jamais synchronisé" before the first one, and what
                // is happening while a sync is in flight.
                .help(app.progress.statusText)
            }
            // Kept in place and merely disabled rather than appearing with the
            // selection: a toolbar whose buttons come and go is unsettling, and
            // this way the affordance is visible before it is needed.
            ToolbarItem {
                Button {
                    selectedActivities = []
                } label: {
                    Label("Fermer le panneau", systemImage: "sidebar.trailing")
                }
                .disabled(selection.isEmpty)
                .help("Fermer le panneau de droite et désélectionner")
            }
            // Grouped, not three loose buttons: the toolbar already carries three
            // items, and six side by side is where it stops reading as a toolbar.
            // These three act on the selected activity and belong together.
            ToolbarItemGroup {
                Button {
                    editor = .create
                } label: {
                    Label("Nouvelle activité", systemImage: "plus")
                }
                .help("Ajouter une activité saisie à la main")

                Button {
                    if let selected { editor = .edit(selected) }
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                .disabled(selected == nil)
                .help("Modifier l'activité sélectionnée")

                Button {
                    pendingDeletion = selected
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                .disabled(selected == nil)
                .help("Supprimer l'activité sélectionnée")
            }
    }
}

/// Which map is filling the window, if any.
private enum ExpandedMap: Equatable {
    case global
    case comparison
    case activity(PersistentIdentifier)
}
