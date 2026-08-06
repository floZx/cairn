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

    /// The sidebar picks a sport; the filter bar refines within it.
    private var effectiveFilter: ActivityFilter {
        var combined = filter
        if case let .sport(sport) = sidebarSelection {
            combined.sports = [sport]
        }
        return combined
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .frame(minWidth: 200)
        } content: {
            switch sidebarSelection {
            case .globalMap:
                GlobalMapView(
                    activities: allActivities.filter(effectiveFilter.matchesPrecisely),
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
                VStack(spacing: 0) {
                    FilterBar(filter: $filter)
                    Divider()
                    ActivityListView(filter: effectiveFilter, selection: $selectedActivity)
                        .id(effectiveFilter)
                }
                .frame(minWidth: 520)
                .searchable(text: $filter.searchText, prompt: "Rechercher une activité")
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
                        Text(app.progress.statusText).font(.caption)
                    }
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
