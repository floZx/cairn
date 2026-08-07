import Foundation
import SwiftData

enum AppModelContainer {
    static let schema = Schema([
        Activity.self, ActivityStreams.self, Athlete.self,
        Lap.self, Gear.self, SyncState.self, DiscardedActivity.self,
    ])

    /// The store file to open, decided in one place rather than scattered across
    /// call sites — every caller that needs to know which store is live goes
    /// through this, `make()` included.
    static func storeFileName(isTesting: Bool, isDemo: Bool) -> String {
        // Testing wins over demo: a test run must never depend on which store a
        // demo flag would otherwise pick, and a demo library on disk is still
        // something a test run should not be touching either.
        if isTesting { return "StravaLocal-tests.store" }
        if isDemo { return "StravaLocal-demo.store" }
        return "StravaLocal.store"
    }

    static func make() throws -> ModelContainer {
        let directory = URL.applicationSupportDirectory.appending(path: "StravaLocal")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // Under test, never the real library. A macOS test bundle runs inside the
        // host application, so `xcodebuild test` executes this app's `init()` and
        // would open — and migrate — 132 MB of irreplaceable data as a side effect
        // of running the suite. That is how this schema change first reached the
        // user's store, before anyone decided it should.
        let isTesting = ProcessInfo.processInfo
            .environment["XCTestConfigurationFilePath"] != nil
        let name = storeFileName(isTesting: isTesting, isDemo: DemoData.isEnabled)
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
