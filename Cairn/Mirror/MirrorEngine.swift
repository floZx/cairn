import Foundation
import SwiftData

/// Where a bootstrap has gotten to, per table: the `uuid` of the last row
/// successfully upserted. Lives in `UserDefaults`, not the SwiftData store,
/// for the same reason `SyncState` lives in the store while describing the
/// relationship with Strava rather than the user's data: this describes the
/// Mac's relationship with Supabase, and a JSON export or a restore of the
/// library must never carry it along.
///
/// Injected rather than hard-coded to `.standard`, so tests can point it at a
/// throwaway suite instead of the suite the test *runner* itself uses —
/// `Tests/JournalStoreTests.swift` follows the same rule for the same reason.
struct MirrorBootstrapCursor: Sendable {
    // `UserDefaults` is thread-safe by Apple's own documentation but not
    // marked `Sendable` in this SDK — the same gap `DetailPaneWidth` and
    // `BackupService` sidestep by taking it as a plain default-argument
    // rather than storing it across an isolation boundary. Storing it here
    // is unavoidable — the cursor has to outlive a single call — so this is
    // the one place in the mirror that asserts, rather than lets the
    // compiler prove, that the type is safe to share.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func key(for table: String) -> String {
        "mirror.bootstrapCursor.\(table)"
    }

    func lastUUID(for table: String) -> String? {
        defaults.string(forKey: key(for: table))
    }

    func setLastUUID(_ uuid: String, for table: String) {
        defaults.set(uuid, forKey: key(for: table))
    }
}

/// Uploads the whole library to Supabase and keeps it there. On the pattern
/// of `SyncEngine`: an actor owning its own `ModelContext`, reporting into a
/// main-actor `MirrorProgress` the same way `SyncEngine` reports into
/// `SyncProgress`.
actor MirrorEngine {
    private let client: MirrorClient
    private let container: ModelContainer
    private let progress: MirrorProgress
    private let context: ModelContext
    private let cursor: MirrorBootstrapCursor

    /// Rows per upsert. Small enough that a batch which fails resends little
    /// on retry; large enough that 852 activities take five requests, not
    /// 852 of them.
    private static let batchSize = 200

    /// Parents before children: a `lap` whose activity is not there yet has
    /// nothing to hang from. The order is fixed rather than derived, because
    /// it is a fact about the schema, and reading it from the schema would be
    /// a way of pretending it might change.
    static let bootstrapOrder: [String] = [
        "athlete", "gear", "day_type", "meal_slot",
        "activity", "activity_streams", "activity_photo", "lap",
        "discarded_activity",
        "nutrition_day", "food_entry", "meal_note",
        "recipe", "recipe_item", "favorite_food", "weight_entry",
    ]

    /// `cursor` takes the already-wrapped `MirrorBootstrapCursor` rather than
    /// a raw `UserDefaults`, and that is not just style: `UserDefaults` is
    /// thread-safe but not `Sendable` in this SDK, and this initializer runs
    /// on the caller's actor, not `MirrorEngine`'s own — a `UserDefaults`
    /// crossing that boundary unwrapped is exactly what Swift 6's region
    /// checker refuses to let through. `MirrorBootstrapCursor` is `Sendable`
    /// by construction, so building it before the call (as the default value
    /// does with `.standard`, and as a test does with its own throwaway
    /// suite) is what makes the crossing legal.
    init(
        client: MirrorClient, container: ModelContainer, progress: MirrorProgress,
        cursor: MirrorBootstrapCursor = MirrorBootstrapCursor(defaults: .standard)
    ) {
        self.client = client
        self.container = container
        self.progress = progress
        self.context = ModelContext(container)
        self.cursor = cursor
    }

    /// Uploads the whole library, table by table, parents first. Safe to call
    /// more than once and safe to interrupt — both are the same property,
    /// idempotence, seen from two angles:
    ///
    /// - A table already fully sent costs no request the second time: its
    ///   cursor already sits past every row on disk, so the first fetch of
    ///   the next call comes back empty and the loop moves straight on.
    /// - A batch that fails, or a cancellation between batches, leaves the
    ///   cursor exactly where the last *successful* batch left it. Nothing
    ///   Supabase has already confirmed is ever sent again; nothing it never
    ///   saw is skipped.
    ///
    /// `resolution=merge-duplicates` on the upsert itself (`MirrorClient`)
    /// is the second half of this guarantee: even a row resent after a crash
    /// mid-batch — the response lost, the write already landed — overwrites
    /// itself rather than duplicating.
    func bootstrap() async throws {
        do {
            guard let userID = await client.userID else {
                throw MirrorError.notConfigured
            }
            for table in Self.bootstrapOrder {
                try Task.checkCancellation()
                try await sendTable(table, userID: userID)
            }
            await finish()
        } catch is CancellationError {
            // Interrupted on purpose — closing the settings window, say —
            // not a failure: nothing here should read as an error to the
            // user. The cursor already reflects every batch that made it
            // out, so the next `bootstrap()` call resumes exactly there.
            await setPhase(.idle)
            throw CancellationError()
        } catch {
            await setPhase(.failed(error.localizedDescription))
            throw error
        }
    }

    /// Dispatches to the concretely-typed fetch for one table. A `switch`
    /// over a fixed, closed list rather than a lookup table, because there is
    /// no way to spell "a `PersistentModel & MirrorRow` type" as a value in
    /// Swift — the type has to appear in source for the compiler to see it.
    private func sendTable(_ table: String, userID: String) async throws {
        switch table {
        case "athlete": try await sendBatches(Athlete.self, table: table, userID: userID)
        case "gear": try await sendBatches(Gear.self, table: table, userID: userID)
        case "day_type": try await sendBatches(DayType.self, table: table, userID: userID)
        case "meal_slot": try await sendBatches(MealSlot.self, table: table, userID: userID)
        case "activity": try await sendBatches(Activity.self, table: table, userID: userID)
        case "activity_streams":
            try await sendBatches(ActivityStreams.self, table: table, userID: userID)
        case "activity_photo":
            try await sendBatches(ActivityPhoto.self, table: table, userID: userID)
        case "lap": try await sendBatches(Lap.self, table: table, userID: userID)
        case "discarded_activity":
            try await sendBatches(DiscardedActivity.self, table: table, userID: userID)
        case "nutrition_day":
            try await sendBatches(NutritionDay.self, table: table, userID: userID)
        case "food_entry": try await sendBatches(FoodEntry.self, table: table, userID: userID)
        case "meal_note": try await sendBatches(MealNote.self, table: table, userID: userID)
        case "recipe": try await sendBatches(Recipe.self, table: table, userID: userID)
        case "recipe_item": try await sendBatches(RecipeItem.self, table: table, userID: userID)
        case "favorite_food":
            try await sendBatches(FavoriteFood.self, table: table, userID: userID)
        case "weight_entry":
            try await sendBatches(WeightEntry.self, table: table, userID: userID)
        default:
            // Unreachable: `bootstrapOrder` is a closed, hand-written list
            // and this `switch` covers every entry in it.
            assertionFailure("table de miroir inconnue : \(table)")
        }
    }

    /// Sends one table's rows, oldest `uuid` first, in batches of
    /// `batchSize`. `Task.checkCancellation()` runs before every batch, not
    /// just once per table: a table of 852 rows is five requests, and
    /// closing the settings window should not have to wait for all five.
    ///
    /// The whole table is fetched once and sliced in Swift, rather than
    /// re-querying SwiftData for each batch with a `uuid > cursor` predicate.
    /// None of the sixteen tables are large enough — 852 activities, 5 672
    /// laps at the top end — for holding one table's rows in memory to
    /// matter next to that.
    ///
    /// The sort is done here, with plain `String` `<`, rather than through
    /// `FetchDescriptor`'s own `sortBy` — measured directly: a
    /// `SortDescriptor(\Model.uuid)` handed to SwiftData does not reliably
    /// return `uuid`s in strict ascending order (observed, repeatedly,
    /// batches of three UUIDs coming back in an order plain `String`
    /// comparison disagrees with). Cursor resumption depends on the ordering
    /// being one true, strict order, so it cannot be left to a comparator
    /// this code does not control.
    private func sendBatches<Model: PersistentModel & MirrorRow>(
        _ type: Model.Type, table: String, userID: String
    ) async throws {
        let all = try context.fetch(FetchDescriptor<Model>())
            .sorted { $0.uuid < $1.uuid }
        guard !all.isEmpty else { return }

        let startIndex: Int
        if let lastUUID = cursor.lastUUID(for: table) {
            // Everything up to and including the cursor already made it to
            // Supabase; resume right after it.
            startIndex = all.firstIndex { $0.uuid > lastUUID } ?? all.count
        } else {
            startIndex = 0
        }

        let total = all.count
        var done = startIndex
        await setPhase(.bootstrapping(table: table, done: done, total: total))

        var index = startIndex
        while index < all.count {
            try Task.checkCancellation()
            let end = min(index + Self.batchSize, all.count)
            let batch = all[index..<end]

            let rows = batch.map { $0.mirrorRow(userID: userID) }
            try await client.upsert(table: table, rows: rows)

            // Advanced only once the upsert has actually returned success —
            // a batch that throws leaves the cursor exactly where the
            // previous one left it, so it is retried in full next time.
            if let last = batch.last?.uuid {
                cursor.setLastUUID(last, for: table)
            }
            done += batch.count
            index = end
            await setPhase(.bootstrapping(table: table, done: done, total: total))
        }
    }

    private func setPhase(_ phase: MirrorPhase) async {
        await MainActor.run { progress.phase = phase }
    }

    private func finish() async {
        await MainActor.run {
            progress.phase = .idle
            progress.lastPushAt = Date()
        }
    }
}
