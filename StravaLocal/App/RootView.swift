import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var filter = ActivityFilter.none
    // See the comment on `ActivityListView.selection`: `Activity.ID` can't be
    // named from this file, so `PersistentIdentifier` is used directly.
    @State private var selectedActivity: PersistentIdentifier?
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
            if allActivities.isEmpty && !app.progress.isRunning {
                WelcomeView()
                    .frame(minWidth: 900, minHeight: 600)
            } else {
                splitView
            }
        }
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
                    region: Binding(
                        get: { filter.region },
                        set: { newRegion in
                            filter.region = newRegion
                            if newRegion != nil { sidebarSelection = .all }
                        }
                    )
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
                ActivityDetailView(activity: selected)
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
                    }
                    // Reserved width: without it the item resizes on every page
                    // and shoves the rest of the toolbar sideways.
                    .frame(minWidth: 120, alignment: .leading)
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
