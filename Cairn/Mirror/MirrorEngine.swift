import Foundation
import SwiftData

/// Where a bootstrap has gotten to, per table: the `uuid` of the last row
/// successfully upserted. Lives in `UserDefaults`, not the SwiftData store,
/// for the same reason `SyncState` lives in the store while describing the
/// relationship with Strava rather than the user's data: this describes the
/// Mac's relationship with Supabase, and a JSON export or a restore of the
/// library must never carry it along.
///
/// Also holds `lastPushAt` — not a per-table cursor, but the same kind of
/// fact (the Mac's relationship with Supabase, not the user's data) and the
/// same storage, so a second `UserDefaults`-backed type was not worth
/// opening for one more key.
///
/// Injected rather than hard-coded to `.standard`, so tests can point it at a
/// throwaway suite instead of the suite the test *runner* itself uses —
/// `Tests/JournalStoreTests.swift` follows the same rule for the same reason.
/// No default value on `MirrorEngine.init` falls back to `.standard`
/// either — see the note there.
struct MirrorBootstrapCursor: Sendable {
    // `UserDefaults` is thread-safe by Apple's own documentation but not
    // marked `Sendable` in this SDK — the same gap `DetailPaneWidth` and
    // `BackupService` sidestep by taking it as a plain default-argument
    // rather than storing it across an isolation boundary. Storing it here
    // is unavoidable — the cursor has to outlive a single call — so this is
    // the one place in the mirror that asserts, rather than lets the
    // compiler prove, that the type is safe to share.
    nonisolated(unsafe) private let defaults: UserDefaults

    private static let lastPushAtKey = "mirror.lastPushAt"

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

    /// `nil` when the mirror has never finished a bootstrap or a push.
    /// `UserDefaults.double(forKey:)` answers `0` for a missing key —
    /// `Tests/DetailPaneWidthTests.swift` already documents the same trap —
    /// so `0` reads back as "never", not as the epoch.
    func lastPushAt() -> Date? {
        let epoch = defaults.double(forKey: Self.lastPushAtKey)
        return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }

    func setLastPushAt(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastPushAtKey)
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
    private let cursor: MirrorBootstrapCursor

    /// Rows per upsert, and per page fetched from SwiftData. Small enough
    /// that a batch which fails resends little on retry; large enough that
    /// 852 activities take five requests, not 852 of them.
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
    /// by construction, so building it before the call is what makes the
    /// crossing legal.
    ///
    /// No default value: an earlier version defaulted this to
    /// `MirrorBootstrapCursor(defaults: .standard)`, which meant any
    /// three-argument call — exactly the shape every other task's test code
    /// uses — would read and write the *test runner's own* preferences. A
    /// stray key surviving between runs there does not just leak state, it
    /// makes a bootstrap silently send nothing: the cursor would already
    /// claim every table done. Whichever code composes the app is expected
    /// to build a real `MirrorBootstrapCursor(defaults: .standard)` and pass
    /// it explicitly — no such call exists yet, `MirrorEngine` has no caller
    /// until task 10 wires one up.
    init(
        client: MirrorClient, container: ModelContainer, progress: MirrorProgress,
        cursor: MirrorBootstrapCursor
    ) {
        self.client = client
        self.container = container
        self.progress = progress
        self.cursor = cursor
    }

    /// Uploads the whole library, table by table, parents first. Safe to call
    /// more than once and safe to interrupt — both are the same property,
    /// idempotence, seen from two angles:
    ///
    /// - A table already fully sent costs no request the second time: its
    ///   cursor already sits past every row on disk, so the page fetched for
    ///   the next call — `uuid > cursor` — comes back empty and the loop
    ///   ends there.
    /// - A batch that fails, or a cancellation between batches, leaves the
    ///   cursor exactly where the last *successful* batch left it. Nothing
    ///   Supabase has already confirmed is ever sent again.
    ///
    /// What this does **not** cover: a row created — or whose `uuid` sorts
    /// before the cursor for some other reason — *between* two bootstrap
    /// attempts is never picked up by a later `bootstrap()` call. The cursor
    /// only ever moves forward through a fixed ascending order; it has no way
    /// to notice a new row that lands behind it. That gap belongs to the
    /// outbox (task 8), which watches every save going forward — bootstrap's
    /// job is strictly the one-time initial upload, not standing outbox
    /// coverage.
    ///
    /// `resolution=merge-duplicates` on the upsert itself (`MirrorClient`)
    /// is the second half of what this *does* guarantee: even a row resent
    /// after a crash mid-batch — the response lost, the write already landed
    /// — overwrites itself rather than duplicating.
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

    /// Reads the persisted "last successful sync" date back into `progress`.
    /// `MirrorProgress` is session state — a fresh instance starts with
    /// `lastPushAt == nil` on every launch — so without this, a mirror that
    /// finished bootstrapping yesterday reads exactly like one that has
    /// never run: `AppEnvironment.restoreLastSyncDate()` solves the identical
    /// problem for `SyncProgress` by reading `SyncState.lastRunAt` back out
    /// of the store: this is the mirror's own version, reading
    /// `MirrorBootstrapCursor.lastPushAt()` back out of `UserDefaults`
    /// instead, since that is where this task's cursor already lives.
    func restoreProgress() async {
        guard let date = cursor.lastPushAt() else { return }
        await MainActor.run {
            // Only while still empty, the same guard `restoreLastSyncDate()`
            // uses: a bootstrap started immediately after this call may well
            // finish first, and a slow read landing after it must not stomp
            // the fresher date back to an older one.
            guard progress.lastPushAt == nil else { return }
            progress.lastPushAt = date
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

    /// Sends one table's rows, oldest `uuid` first, in pages of `batchSize`,
    /// fetched by key (`uuid > cursor`) rather than by position. `Task.checkCancellation()`
    /// runs before every page, not just once per table: a table of 852 rows
    /// is five requests, and closing the settings window should not have to
    /// wait for all five.
    ///
    /// By key, not by `fetchOffset` — an earlier version paginated by
    /// position (`fetchOffset`/`fetchLimit`, `offset` advanced by
    /// `batch.count`), and a reproduction of a row deleted concurrently,
    /// mid-bootstrap, behind an already-sent page caught the bug that shape
    /// has: a delete behind the cursor shifts every row after it one slot to
    /// the left, so the position the next page starts reading from now
    /// points one row *past* where it used to — the row that used to sit
    /// there is skipped, permanently, since the cursor only ever advances
    /// and nothing else will ever notice it was missed. Reading `uuid >
    /// cursor` fresh on every page has no such failure mode: a deletion
    /// changes which rows exist, never what "greater than this uuid" means
    /// for the ones that still do.
    ///
    /// Each page opens its own `ModelContext` rather than reusing one held by
    /// the actor across the whole bootstrap — measured, not assumed: at
    /// roughly 12 KB per attribute, `ActivityStreams`' eleven `Data?`
    /// properties sit **inline** in the SQLite store rather than behind
    /// `.externalStorage`, which only takes effect above CoreData's own
    /// externalization threshold. A single long-lived context that fetches
    /// every `ActivityStreams` row for the whole bootstrap keeps every one of
    /// those blobs resident until the entire run finishes, ~320 MB on the
    /// real library, none of it ever touched — `mirrorRow` only reads
    /// `pointCount` and writes a `storage_path` string, never the bytes
    /// themselves. A fresh, short-lived context per page releases the
    /// previous page's rows — blobs included — the moment the page is sent.
    ///
    /// The sort passes an explicit `.lexical` comparator rather than
    /// `SortDescriptor(\Model.uuid)`'s default — measured, not assumed again:
    /// `SortDescriptor` on a `String` defaults to a *localized*, numeric-aware
    /// comparator, so `"0E9AB009…"` sorts before `"0E10DDFC…"` (9 before 10,
    /// digit-run compared as a number) even though plain `String` `<`
    /// disagrees. `.lexical` matches `<` exactly — checked against a full
    /// 852-row table, not just spot-checked. Cursor resumption depends on the
    /// ordering being the one, single order every page and every run agrees
    /// on, so it cannot be left to whichever comparator happens to be the
    /// default.
    private func sendBatches<Model: PersistentModel & MirrorRow>(
        _ type: Model.Type, table: String, userID: String
    ) async throws {
        let total = try ModelContext(container).fetchCount(FetchDescriptor<Model>())
        guard total > 0 else { return }

        // A count, not a fetch: nothing about "how many are already sent"
        // needs a single row's data in memory, only for the progress figure
        // shown while the loop below does the real work.
        var done = try alreadySentCount(Model.self, table: table)
        await setPhase(.bootstrapping(table: table, done: done, total: total))

        while true {
            try Task.checkCancellation()

            // The cursor is re-read on every iteration, not cached at the
            // top of the loop: it is the position, and re-reading it after
            // each successful page is what makes a deletion elsewhere in the
            // table harmless rather than something this loop has to reason
            // about.
            let pageContext = ModelContext(container)
            var descriptor: FetchDescriptor<Model>
            if let lastUUID = cursor.lastUUID(for: table) {
                descriptor = FetchDescriptor<Model>(
                    predicate: #Predicate<Model> { $0.uuid > lastUUID }
                )
            } else {
                descriptor = FetchDescriptor<Model>()
            }
            descriptor.sortBy = [SortDescriptor(\Model.uuid, comparator: .lexical)]
            descriptor.fetchLimit = Self.batchSize
            let batch = try pageContext.fetch(descriptor)
            if batch.isEmpty { break }

            let rows = batch.map { $0.mirrorRow(userID: userID) }
            try await client.upsert(table: table, rows: rows)

            // Advanced only once the upsert has actually returned success —
            // a batch that throws leaves the cursor exactly where the
            // previous one left it, so it is retried in full next time.
            if let last = batch.last?.uuid {
                cursor.setLastUUID(last, for: table)
            }
            done += batch.count
            await setPhase(.bootstrapping(table: table, done: done, total: total))
        }
    }

    /// How many of this table's rows the cursor already accounts for — a
    /// count, so it costs nothing beyond what `sendBatches` already pays for
    /// `total`.
    private func alreadySentCount<Model: PersistentModel & MirrorRow>(
        _ type: Model.Type, table: String
    ) throws -> Int {
        guard let lastUUID = cursor.lastUUID(for: table) else { return 0 }
        return try ModelContext(container).fetchCount(
            FetchDescriptor<Model>(predicate: #Predicate<Model> { $0.uuid <= lastUUID })
        )
    }

    private func setPhase(_ phase: MirrorPhase) async {
        await MainActor.run { progress.phase = phase }
    }

    private func finish() async {
        let now = Date()
        cursor.setLastPushAt(now)
        await MainActor.run {
            progress.phase = .idle
            progress.lastPushAt = now
        }
    }
}
