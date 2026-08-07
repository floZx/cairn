import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var filter = ActivityFilter.none
    // See the comment on `ActivityListView.selection`: `Activity.ID` can't be
    // named from this file, so `PersistentIdentifier` is used directly.
    @State private var selectedActivities: Set<PersistentIdentifier> = []
    /// Which map, if any, is filling the window.
    @State private var expandedMap: ExpandedMap?
    /// Shared with every map so the chosen background and colour carry over.
    @AppStorage(MapStyle.storageKey) private var expandedStyle: MapStyle = .standard
    @AppStorage(TrackColor.storageKey) private var expandedTrackColor: TrackColor = .accent
    @Query private var allActivities: [Activity]

    /// The selected activities, whatever their number.
    private var selection: [Activity] {
        allActivities.filter { selectedActivities.contains($0.id) }
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
        let predicate = filter.predicate()
        return allActivities.filter { activity in
            ((try? predicate.evaluate(activity)) ?? true)
                && filter.matchesPrecisely(activity)
        }
    }

    var body: some View {
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
    }

    /// A map on its own, with the sidebar and the detail pane out of the way.
    @ViewBuilder
    private func fullWindowMap(_ expanded: ExpandedMap) -> some View {
        let map = Group {
            switch expanded {
            case .global:
                GlobalMapView(
                    activities: mapActivities,
                    region: regionBinding
                )
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
                        onExpand: { expandedMap = .global }
                    )
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

    @ViewBuilder
    private var detailColumn: some View {
        if showsGlobalMap {
            collapsedDetailColumn
        } else if let selected {
            ActivityDetailView(
                activity: selected,
                onExpandMap: { expandedMap = .activity(selected.id) }
            )
        } else if selection.count > 1 {
            ComparisonMapView(activities: selection)
        } else {
            collapsedDetailColumn
        }
    }

    /// Nothing worth a pane: beside the global map, or with nothing selected.
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
                .disabled(selection.isEmpty || showsGlobalMap)
                .help("Fermer le panneau de droite et désélectionner")
            }
    }
}

/// Which map is filling the window, if any.
private enum ExpandedMap: Equatable {
    case global
    case activity(PersistentIdentifier)
}
