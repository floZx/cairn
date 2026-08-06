import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var filter = ActivityFilter.none
    // See the comment on `ActivityListView.selection`: `Activity.ID` can't be
    // named from this file, so `PersistentIdentifier` is used directly.
    @State private var selectedActivity: PersistentIdentifier?
    /// Which map, if any, is filling the window.
    @State private var expandedMap: ExpandedMap?
    @Query private var allActivities: [Activity]

    private var selected: Activity? {
        allActivities.first { $0.id == selectedActivity }
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
                    selection: $selectedActivity,
                    region: regionBinding
                )
            case let .activity(id):
                if let activity = allActivities.first(where: { $0.id == id }) {
                    ActivityMapView(
                        coordinates: activity.streams?.coordinates.isEmpty == false
                            ? activity.streams!.coordinates
                            : activity.simplifiedCoordinates,
                        style: expandedStyle
                    )
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

    /// Shared with both maps so the chosen background carries over.
    @AppStorage(MapStyle.storageKey) private var expandedStyle: MapStyle = .standard

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

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, filter: $filter)
                .frame(minWidth: 260)
        } content: {
            switch sidebarSelection {
            case .globalMap:
                GlobalMapView(
                    activities: mapActivities,
                    selection: $selectedActivity,
                    region: regionBinding,
                    onExpand: { expandedMap = .global }
                )
                .frame(minWidth: 520)
            default:
                ActivityListView(filter: filter, selection: $selectedActivity)
                    .id(filter)
                    .frame(minWidth: 520)
                    .searchable(
                        text: $filter.searchText, prompt: "Rechercher une activité"
                    )
            }
        } detail: {
            if let selected {
                ActivityDetailView(
                    activity: selected,
                    onExpandMap: { expandedMap = .activity(selected.id) }
                )
            } else {
                ContentUnavailableView(
                    "Aucune activité sélectionnée", systemImage: "figure.run",
                    description: Text("Choisissez une activité dans la liste.")
                )
            }
        }
        .toolbar {
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
        }
    }
}

/// Which map is filling the window, if any.
private enum ExpandedMap: Equatable {
    case global
    case activity(PersistentIdentifier)
}
