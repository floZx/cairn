import Foundation
import SwiftData

enum AppModelContainer {
    static let schema = Schema([
        Activity.self, ActivityStreams.self, Athlete.self,
        Lap.self, Gear.self, SyncState.self, DiscardedActivity.self,
        ActivityPhoto.self,
        // Nutrition — added as a block: SwiftData treats new models as a
        // lightweight migration, existing activity data is untouched.
        DayType.self, MealSlot.self, NutritionDay.self, FoodEntry.self,
        MealNote.self, Recipe.self, RecipeItem.self, FavoriteFood.self,
        WeightEntry.self,
    ])

    /// The store file to open, decided in one place rather than scattered across
    /// call sites — every caller that needs to know which store is live goes
    /// through this, `make()` included.
    static func storeFileName(isTesting: Bool, isDemo: Bool) -> String {
        // Testing wins over demo: a test run must never depend on which store a
        // demo flag would otherwise pick, and a demo library on disk is still
        // something a test run should not be touching either.
        if isTesting { return "Cairn-tests.store" }
        if isDemo { return "Cairn-demo.store" }
        return "Cairn.store"
    }

    static func make() throws -> ModelContainer {
        let directory = URL.applicationSupportDirectory.appending(path: "Cairn")
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
        // Before opening anything: an unmigrated library from the app's former
        // name would otherwise be shadowed by a brand-new empty store.
        try LegacyStoreMigration.run(
            from: URL.applicationSupportDirectory
                .appending(path: LegacyStoreMigration.legacyDirectoryName),
            to: directory
        )
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
