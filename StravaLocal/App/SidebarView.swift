import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case all
    case sport(SportType)
    case globalMap
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query private var activities: [Activity]

    private var sportCounts: [(sport: SportType, count: Int)] {
        Dictionary(grouping: activities, by: \.sportType)
            .map { (sport: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Toutes les activités", systemImage: "list.bullet")
                    .badge(activities.count)
                    .tag(SidebarItem.all)
                Label("Carte globale", systemImage: "map")
                    .tag(SidebarItem.globalMap)
            }

            Section("Sports") {
                ForEach(sportCounts, id: \.sport) { entry in
                    Label(entry.sport.displayName, systemImage: entry.sport.symbolName)
                        .badge(entry.count)
                        .tag(SidebarItem.sport(entry.sport))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
