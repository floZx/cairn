import SwiftUI
import SwiftData

@main
struct StravaLocalApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try AppModelContainer.make()
        } catch {
            fatalError("Impossible d'ouvrir la base locale : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Text("StravaLocal")
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(container)
    }
}
