import Foundation
import SwiftData

enum AppModelContainer {
    static let schema = Schema([
        Activity.self, ActivityStreams.self, Athlete.self,
        Lap.self, Gear.self, SyncState.self,
    ])

    static func make() throws -> ModelContainer {
        let directory = URL.applicationSupportDirectory.appending(path: "StravaLocal")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // A separate file in demo mode, and that is the whole safety of it: the
        // real library is never opened, so nothing can write to it.
        let name = DemoData.isEnabled ? "StravaLocal-demo.store" : "StravaLocal.store"
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appending(path: name)
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
