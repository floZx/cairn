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
    private static let cursorKeyPrefix = "mirror.bootstrapCursor."

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func key(for table: String) -> String {
        "\(Self.cursorKeyPrefix)\(table)"
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

    /// Erases every position this cursor has ever recorded: every table's
    /// `lastUUID` and `lastPushAt`. `AppEnvironment.forgetMirror()`'s
    /// counterpart, on the store side, to `SecretStore.clearMirror()` on the
    /// keychain side.
    ///
    /// Without this, forgetting a mirror and reconfiguring a *different*
    /// Supabase project would leave the old project's progress in place:
    /// `sendBatches` only ever fetches `uuid > cursor` (see its own doc
    /// comment), so a bootstrap against the new project would silently skip
    /// every row sorting before the stale cursor — rows the new project has
    /// never received, mistaken for ones already sent because a project it
    /// has nothing to do with once received them.
    ///
    /// Walks `UserDefaults`' own dictionary rather than a fixed table list
    /// (`MirrorEngine.bootstrapOrder`, say): a table that used to be part of
    /// that list and no longer is would otherwise leave an orphaned key
    /// behind forever, and nothing here should have to be kept in sync with
    /// that list to stay correct.
    func clear() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.cursorKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: Self.lastPushAtKey)
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

    /// Rows per blob-upload page — far smaller than `batchSize`, and
    /// deliberately so: at ~12 KB per attribute, a page of `ActivityStreams`
    /// at *this* table's own `batchSize` (200) would hold ~26 MB of blobs
    /// in memory at once (11 × 12 KB × 200). `blobBatchSize` keeps that same
    /// arithmetic under a megabyte a page instead — measured, not guessed;
    /// see the probe in the task 7 report for the resident figures this size
    /// was picked against.
    private static let blobBatchSize = 5

    /// Supabase Storage bucket ids, matching `supabase/schema.sql`'s
    /// `storage.buckets` seed exactly — a typo here would upload to a bucket
    /// that silently doesn't exist rather than fail loudly.
    private static let photosBucket = "photos"
    private static let streamsBucket = "streams"

    /// The sixteen tables, parents before children — a convenience, not a
    /// constraint. `supabase/schema.sql` carries **no foreign key** between
    /// mirror tables, deliberately and in its own opening comment: a link is
    /// the child's own `activity_uuid`, `meal_slot_uuid`, and so on, precisely
    /// so that arrival order — which no synchronisation protocol guarantees —
    /// cannot make a row illegal. A `lap` sent before its activity is accepted
    /// and hangs from an `activity_uuid` that resolves the moment the parent
    /// lands.
    ///
    /// What the order buys is a bootstrap interrupted halfway reading like
    /// something rather than nothing: the activities are there before the laps
    /// that describe them. `push()` makes no such effort at all — it visits
    /// whatever tables the outbox names, alphabetically (`byTable.keys.sorted()`),
    /// which would be a bug if any of this were load-bearing.
    ///
    /// Fixed rather than derived from the schema all the same: sixteen names
    /// in one place, read by two `switch`es that have to cover exactly them.
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
            // Before any row: a row's `storage_path` is emitted
            // unconditionally (task 5), so uploading first means the object
            // it names already exists by the time the row lands — rather
            // than merely "eventually will", once a later call catches up.
            // Blobs first when they work; never blobs *instead of* rows —
            // an object that will not upload is counted and skipped, see
            // `uploadPendingBlobs()`.
            try await uploadPendingBlobs()
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

    /// Uploads what changed locally since the last push: pending blobs
    /// first (same reasoning as `bootstrap()`, see `uploadPendingBlobs()`),
    /// then the outbox (task 8), replayed table by table. `bootstrap()`'s
    /// counterpart for everything after the initial upload — the standing
    /// coverage that notices a row created, edited, or deleted behind the
    /// cursor, which `bootstrap()` explicitly does not.
    ///
    /// Safe to call again after any failure, for the same reason
    /// `bootstrap()` is: an outbox entry is deleted only once the request
    /// that carried its row has actually come back with success. A network
    /// failure, a cancelled task, or the app being killed mid-push leaves
    /// every entry not yet confirmed exactly where it was — nothing Supabase
    /// has not already accepted is ever dropped from the trail.
    ///
    /// Grouped by `(table, uuid)` first, keeping only the most recent entry
    /// per row to *decide what to send*: ten edits to the same row before a
    /// single push leave ten outbox entries (task 8 does not deduplicate),
    /// and for a create-then-delete pair only the last one describes what
    /// Supabase should end up holding. `changedAt` is unreliable *within*
    /// one save (several entries from the same save land at the same
    /// microsecond) but that never matters here: `MirrorRecorder.pendingEntries`
    /// already collapses one save down to at most one entry per row, so two
    /// entries sharing a key only ever come from two distinct saves, and
    /// `changedAt` orders those correctly — exactly the create-then-delete
    /// case it exists for.
    ///
    /// **Every stale entry a row had *at the moment this call started
    /// reading the outbox*** is purged once that row is resolved — not a
    /// second, later query for `(table, uuid)`. That distinction is load-
    /// bearing: a later query would also catch an entry `MirrorRecorder`
    /// writes *during* the HTTP round trip this call is waiting on — the
    /// user edits the very row this push is sending, between the request
    /// going out and the response coming back — and erase the record of an
    /// edit that was never actually sent. `entriesByRow` below is built once,
    /// from the single fetch at the top of this method, and `purge` only
    /// ever deletes objects out of that fixed set — nothing this call did
    /// not itself read is ever at risk of being purged.
    func push() async throws {
        do {
            guard let userID = await client.userID else {
                throw MirrorError.notConfigured
            }
            // Before any row, for the same reason `bootstrap()` does this
            // first: a row's `storage_path` is emitted unconditionally, so a
            // photo or a stream added after the initial bootstrap must have
            // its bytes in Storage before its row goes out, not merely
            // "eventually will" once some later `bootstrap()` catches up.
            try await uploadPendingBlobs()

            let outboxContext = ModelContext(container)
            let entries = try outboxContext.fetch(FetchDescriptor<MirrorOutbox>())

            // An empty outbox still counts as a clean finish, on the same
            // reasoning as `bootstrap()` calling `finish()` unconditionally
            // even when every table turned out empty: "nothing pending" is
            // itself the caught-up state, not a reason to leave `lastPushAt`
            // stale until the next change happens to arrive.
            if !entries.isEmpty {
                // Every entry fetched just now, grouped by row — the fixed
                // universe `purge` is ever allowed to delete from. Built
                // *before* anything awaits the network, so nothing recorded
                // after this point can appear in it.
                var entriesByRow: [String: [MirrorOutbox]] = [:]
                for entry in entries {
                    entriesByRow[Self.rowKey(table: entry.table, uuid: entry.rowUUID), default: []]
                        .append(entry)
                }

                var latestByRow: [String: MirrorOutbox] = [:]
                for entry in entries {
                    let key = Self.rowKey(table: entry.table, uuid: entry.rowUUID)
                    if let existing = latestByRow[key], existing.changedAt > entry.changedAt {
                        continue
                    }
                    latestByRow[key] = entry
                }
                let byTable = Dictionary(grouping: latestByRow.values, by: \.table)

                var done = 0
                let total = latestByRow.count
                await setPhase(.pushing(done: done, total: total))

                for table in byTable.keys.sorted() {
                    try Task.checkCancellation()
                    guard let tableEntries = byTable[table] else { continue }
                    let sent = try await pushTable(
                        table, entries: tableEntries, userID: userID,
                        entriesByRow: entriesByRow, outboxContext: outboxContext
                    )
                    done += sent
                    await setPhase(.pushing(done: done, total: total))
                }
            }

            await finish()
        } catch is CancellationError {
            // Same reasoning as `bootstrap()`: closing the settings window
            // mid-push is not a failure and must not read as one.
            await setPhase(.idle)
            throw CancellationError()
        } catch {
            await setPhase(.failed(error.localizedDescription))
            throw error
        }
    }

    private static func rowKey(table: String, uuid: String) -> String { "\(table)|\(uuid)" }

    /// The page size a push uses for one table's non-deletion batch — the
    /// same two constants `bootstrap()` already picked and already
    /// justified (`batchSize`, `blobBatchSize`), reused rather than
    /// reinvented. `activity_streams` and `activity_photo` carry the same
    /// inline blob columns here as they do during a bootstrap — a page of
    /// `activity_streams` at the ordinary `batchSize` would hold the same
    /// ~26 MB of blobs resident that `blobBatchSize`'s doc comment measures
    /// for `bootstrap()`, and an incremental push has no more excuse to pay
    /// that than a full one does.
    private static func pushBatchSize(for table: String) -> Int {
        switch table {
        case "activity_streams", "activity_photo": blobBatchSize
        default: batchSize
        }
    }

    /// Splits a list into consecutive pieces of at most `size`. Plain
    /// `Array` chunking has no standard-library spelling; a private helper
    /// rather than pulling in anything external, on the "no new SPM
    /// dependency" constraint the whole plan holds to.
    private static func chunked(_ items: [String], size: Int) -> [[String]] {
        guard size > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
        var pages: [[String]] = []
        var index = items.startIndex
        while index < items.endIndex {
            let end = items.index(index, offsetBy: size, limitedBy: items.endIndex) ?? items.endIndex
            pages.append(Array(items[index..<end]))
            index = end
        }
        return pages
    }

    /// Dispatches to the concretely-typed push for one table — the same
    /// closed `switch` as `sendTable`, for the same reason: there is no way
    /// to spell "a `PersistentModel & MirrorRow` type" as a value. Returns
    /// how many outbox entries this table resolved, for `push()`'s progress
    /// count.
    private func pushTable(
        _ table: String, entries: [MirrorOutbox], userID: String,
        entriesByRow: [String: [MirrorOutbox]], outboxContext: ModelContext
    ) async throws -> Int {
        switch table {
        case "athlete":
            return try await pushRows(Athlete.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "gear":
            return try await pushRows(Gear.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "day_type":
            return try await pushRows(DayType.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "meal_slot":
            return try await pushRows(MealSlot.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "activity":
            return try await pushRows(Activity.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "activity_streams":
            return try await pushRows(ActivityStreams.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "activity_photo":
            return try await pushRows(ActivityPhoto.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "lap":
            return try await pushRows(Lap.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "discarded_activity":
            return try await pushRows(DiscardedActivity.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "nutrition_day":
            return try await pushRows(NutritionDay.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "food_entry":
            return try await pushRows(FoodEntry.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "meal_note":
            return try await pushRows(MealNote.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "recipe":
            return try await pushRows(Recipe.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "recipe_item":
            return try await pushRows(RecipeItem.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "favorite_food":
            return try await pushRows(FavoriteFood.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "weight_entry":
            return try await pushRows(WeightEntry.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        default:
            // Unreachable: every entry's `table` was written by
            // `MirrorRecorder` from `MirrorRow.mirrorTable`, and that
            // protocol is conformed by exactly the sixteen models this
            // `switch` covers.
            assertionFailure("table de miroir inconnue : \(table)")
            return 0
        }
    }

    /// One table's slice of a push: the non-deletion entries paged into
    /// `pushBatchSize(for:)`-sized upserts, the deletion entries as one
    /// `PATCH` apiece — a soft delete has no batch form, since PostgREST's
    /// `?uuid=eq.<uuid>` targets one row.
    ///
    /// Both `entries` and `deletions`/`updates` derived from it are sorted
    /// by `(changedAt, rowUUID)` before any paging or requesting happens —
    /// not for correctness (nothing here depends on visiting rows in any
    /// particular order) but so that which rows land in which page, and
    /// which deletion is attempted before which, is the same on every call
    /// with the same outbox contents rather than left to `Dictionary`'s
    /// unspecified iteration order. `rowUUID` breaks a `changedAt` tie the
    /// same way it would matter to: two entries from the same save share a
    /// microsecond (see `push()`'s own doc comment), so `changedAt` alone
    /// cannot be trusted to order them.
    ///
    /// Each page fetches its `Model` rows through a **fresh `ModelContext`**,
    /// never the long-lived `outboxContext` this function also receives —
    /// the same fix, for the same measured reason, `sendBatches`' own doc
    /// comment explains at length: `ActivityStreams`' eleven `Data?`
    /// properties sit inline in the SQLite store, and a context that
    /// accumulates every page's rows across a whole table would hold every
    /// one of those blobs resident for the rest of the push. `outboxContext`
    /// itself stays put throughout — it is the one context every
    /// `MirrorOutbox` object in `entriesByRow` is registered with, and
    /// `purge` can only `delete` an object through the context that holds
    /// it.
    ///
    /// Entries are purged from the outbox only once the request that
    /// resolves them has actually returned success: each page purges right
    /// after the upsert that carried it returns, giving partial credit for
    /// whatever page failed after — the pages before it stay purged, the one
    /// that failed and every one after stay in the outbox; each deletion
    /// purges on its own, right after its own `PATCH` returns, so a deletion
    /// that fails midway through a table leaves the ones before it gone from
    /// the outbox and the ones from it onward — including itself —
    /// untouched.
    private func pushRows<Model: PersistentModel & MirrorRow>(
        _ type: Model.Type, table: String, entries: [MirrorOutbox], userID: String,
        entriesByRow: [String: [MirrorOutbox]], outboxContext: ModelContext
    ) async throws -> Int {
        func ordered(_ items: [MirrorOutbox]) -> [MirrorOutbox] {
            items.sorted { lhs, rhs in
                lhs.changedAt != rhs.changedAt
                    ? lhs.changedAt < rhs.changedAt : lhs.rowUUID < rhs.rowUUID
            }
        }
        let deletions = ordered(entries.filter(\.isDeletion))
        let updates = ordered(entries.filter { !$0.isDeletion })
        var processed = 0

        if !updates.isEmpty {
            // `changedAt` per row, for stamping `edited_at` below — the
            // author's own clock, read straight from the entry that decided
            // this row needed sending, never the network's.
            let changedAtByUUID = Dictionary(
                uniqueKeysWithValues: updates.map { ($0.rowUUID, $0.changedAt) }
            )
            let pageSize = Self.pushBatchSize(for: table)
            for page in Self.chunked(updates.map(\.rowUUID), size: pageSize) {
                try Task.checkCancellation()
                let pageUUIDs = Set(page)
                let pageContext = ModelContext(container)
                let models = try pageContext.fetch(
                    FetchDescriptor<Model>(
                        predicate: #Predicate<Model> { pageUUIDs.contains($0.uuid) }
                    )
                )
                // A row named by an entry but absent from the store —
                // created and deleted before the recorder ever saw it as a
                // deletion — has nothing left to send; the ones that do
                // exist still go.
                if !models.isEmpty {
                    let rows = models.map { model -> [String: MirrorValue] in
                        var row = model.mirrorRow(userID: userID)
                        if let changedAt = changedAtByUUID[model.uuid] {
                            row["edited_at"] = .date(changedAt)
                        }
                        return row
                    }
                    try await client.upsert(table: table, rows: rows)
                }
                // Reached only once the request above actually returned
                // success, or there was nothing to send: every entry in this
                // page is accounted for now, found locally or not — a
                // missing row is a non-event, not a reason to keep retrying
                // it forever.
                try purge(
                    table: table, uuids: pageUUIDs, entriesByRow: entriesByRow,
                    context: outboxContext
                )
                processed += page.count
            }
        }

        for deletion in deletions {
            try Task.checkCancellation()
            try await client.softDelete(
                table: table, uuid: deletion.rowUUID, userID: userID, deletedAt: deletion.changedAt
            )
            try purge(
                table: table, uuids: [deletion.rowUUID], entriesByRow: entriesByRow,
                context: outboxContext
            )
            processed += 1
        }

        return processed
    }

    /// Deletes every outbox entry the *initial* fetch at the top of `push()`
    /// found for the given rows of one table — looked up in `entriesByRow`,
    /// a fixed snapshot built once before any request went out, never by
    /// re-querying the store here.
    ///
    /// That distinction is the whole point: a fresh query at this point
    /// would also match an entry `MirrorRecorder` wrote *after* the snapshot
    /// was taken — the row this call is about to mark resolved, edited again
    /// by the user while the request for its *previous* state was still in
    /// flight. Deleting that entry would erase the only record that the
    /// second edit ever happened, since nothing else will ever revisit it:
    /// the outbox is its sole trail. Restricting the delete to objects this
    /// call already holds a reference to — the ones `entriesByRow` was built
    /// from — makes that impossible: an entry that did not exist yet when
    /// `push()` took its snapshot cannot be in `entriesByRow`, so it cannot
    /// be purged by this push no matter how the timing lines up. It waits
    /// for the next call, exactly like any other unpushed change.
    ///
    /// `MirrorOutbox` is not a `MirrorRow` (see its own doc comment), so
    /// this save needs no `MirrorBookkeeping.perform` wrapper — only a save
    /// that stamps a mirrored model needs that exemption, and this touches
    /// none.
    private func purge(
        table: String, uuids: Set<String>, entriesByRow: [String: [MirrorOutbox]],
        context: ModelContext
    ) throws {
        var any = false
        for uuid in uuids {
            guard let stale = entriesByRow[Self.rowKey(table: table, uuid: uuid)] else { continue }
            for entry in stale {
                context.delete(entry)
                any = true
            }
        }
        guard any else { return }
        try context.save()
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

    /// Uploads every blob Storage does not have yet: `ActivityPhoto.data`
    /// first, then `ActivityStreams`' eleven streams packaged into the one
    /// JSON object per row task 5's schema comment describes. Called by
    /// `bootstrap()`, and safe to call on its own — `Tests/MirrorBlobTests.swift`
    /// does exactly that.
    ///
    /// A row with no bytes yet — a photo whose Strava download hasn't landed,
    /// an `ActivityStreams` GPX import still in flight — is left untouched
    /// rather than marked done: `mirroredAt` only ever moves from `nil` to a
    /// date, never back, so leaving it `nil` is what lets a later call catch
    /// the bytes once they exist. Visiting it again costs a fetch, never an
    /// HTTP request — the whole point, since 852 activities synced before
    /// their photos would otherwise cost 852 requests for nothing every
    /// bootstrap.
    ///
    /// One upload at a time, never in parallel: 342 photos launched together
    /// would saturate the link and the free egress quota alike.
    ///
    /// An upload that fails is **counted, not thrown**: it leaves `mirroredAt`
    /// nil so a later call retries it, and the sweep carries on to the next
    /// object. Storage's own policies are the one part of this mirror never
    /// exercised against a real project — `owner = auth.uid()` against
    /// `owner_id` on recent Supabase — and a durable 403 there would
    /// otherwise fail `bootstrap()` before a single scalar row had left the
    /// Mac, since blobs go first. A row pointing at an object that is not
    /// there is a degraded read for the web; nothing at all is no read. The
    /// tally reaches the user through `MirrorProgress.failedUploads`.
    ///
    /// Returns that tally, so `Tests/MirrorBlobTests.swift` can assert on it
    /// without going through the main actor.
    @discardableResult
    func uploadPendingBlobs() async throws -> Int {
        guard let userID = await client.userID else {
            throw MirrorError.notConfigured
        }
        var failures = 0
        failures += try await uploadPendingPhotos(userID: userID)
        failures += try await uploadPendingStreams(userID: userID)
        // Assigned, never accumulated: a run that finally gets its objects
        // through must clear what the previous one reported.
        await MainActor.run { progress.failedUploads = failures }
        return failures
    }

    /// Pages through `ActivityPhoto` by `uuid`, `blobBatchSize` at a time,
    /// uploading whichever of them still has `data` and marking it with
    /// `mirroredAt`. Structured exactly like `sendBatches`: a fresh
    /// `ModelContext` per page, an explicit `.lexical` comparator on the
    /// sort, `try Task.checkCancellation()` before every page — the same
    /// three fixes that section's doc comment explains, for the same
    /// reasons, applied to a table that carries actual image bytes rather
    /// than a `storage_path` string.
    ///
    /// Paged by `uuid > lastUUID` with `lastUUID` advanced to the last row of
    /// *every* page — including one where every photo was skipped for having
    /// no bytes — rather than by `mirroredAt == nil` alone: without that
    /// advance, a page consisting entirely of not-yet-downloaded photos would
    /// never change from one iteration to the next, looping forever instead
    /// of finishing the sweep and returning control to `bootstrap()`.
    ///
    /// Returns how many uploads failed — see `uploadPendingBlobs()` for why a
    /// failure is counted rather than thrown.
    private func uploadPendingPhotos(userID: String) async throws -> Int {
        var failures = 0
        var lastUUID: String?
        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            var descriptor: FetchDescriptor<ActivityPhoto>
            if let cursorUUID = lastUUID {
                descriptor = FetchDescriptor<ActivityPhoto>(
                    predicate: #Predicate<ActivityPhoto> {
                        $0.mirroredAt == nil && $0.uuid > cursorUUID
                    }
                )
            } else {
                descriptor = FetchDescriptor<ActivityPhoto>(
                    predicate: #Predicate<ActivityPhoto> { $0.mirroredAt == nil }
                )
            }
            descriptor.sortBy = [SortDescriptor(\.uuid, comparator: .lexical)]
            descriptor.fetchLimit = Self.blobBatchSize
            let page = try context.fetch(descriptor)
            if page.isEmpty { break }
            lastUUID = page.last?.uuid

            for photo in page {
                try Task.checkCancellation()
                guard let data = photo.data else { continue }
                do {
                    try await client.upload(
                        bucket: Self.photosBucket,
                        path: photo.blobStoragePath(userID: userID),
                        data: data,
                        // Nothing downstream of the Strava fetch records the
                        // real MIME type; every photo Strava has ever served
                        // this app has been a JPEG in practice.
                        contentType: "image/jpeg"
                    )
                    photo.mirroredAt = Date()
                } catch is CancellationError {
                    // Interrupting is not failing: it must reach `bootstrap()`
                    // as itself, never as one more counted upload.
                    throw CancellationError()
                } catch {
                    // `mirroredAt` deliberately left nil: this object is owed,
                    // and the next sweep is what pays it.
                    failures += 1
                }
            }
            // Bookkeeping, not a change to mirror: `ActivityPhoto` is itself a
            // `MirrorRow`, so without this the recorder would file one outbox
            // entry per photo uploaded and the next push would re-upsert the
            // whole table for nothing.
            try MirrorBookkeeping.perform { try context.save() }
        }
        return failures
    }

    /// `ActivityStreams`' counterpart to `uploadPendingPhotos`: same paging,
    /// same cursor-advances-regardless-of-skips reasoning, but each row
    /// contributes at most one upload — its `packagedStreams` JSON object,
    /// skipped only when every one of the eleven streams is empty (a row
    /// created before any GPX or Strava data arrived).
    ///
    /// Returns how many uploads failed, same terms as `uploadPendingPhotos`.
    private func uploadPendingStreams(userID: String) async throws -> Int {
        var failures = 0
        var lastUUID: String?
        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            var descriptor: FetchDescriptor<ActivityStreams>
            if let cursorUUID = lastUUID {
                descriptor = FetchDescriptor<ActivityStreams>(
                    predicate: #Predicate<ActivityStreams> {
                        $0.mirroredAt == nil && $0.uuid > cursorUUID
                    }
                )
            } else {
                descriptor = FetchDescriptor<ActivityStreams>(
                    predicate: #Predicate<ActivityStreams> { $0.mirroredAt == nil }
                )
            }
            descriptor.sortBy = [SortDescriptor(\.uuid, comparator: .lexical)]
            descriptor.fetchLimit = Self.blobBatchSize
            let page = try context.fetch(descriptor)
            if page.isEmpty { break }
            lastUUID = page.last?.uuid

            for streams in page {
                try Task.checkCancellation()
                let pieces = streams.packagedStreams
                guard !pieces.isEmpty else { continue }
                let payload = pieces.mapValues { $0.base64EncodedString() }
                let body: Data
                do {
                    body = try JSONSerialization.data(withJSONObject: payload)
                } catch {
                    throw MirrorError.encodingFailed(String(describing: error))
                }
                do {
                    try await client.upload(
                        bucket: Self.streamsBucket,
                        path: streams.blobStoragePath(userID: userID),
                        data: body,
                        contentType: "application/json"
                    )
                    streams.mirroredAt = Date()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Counted, not fatal — `uploadPendingBlobs()` explains why.
                    failures += 1
                }
            }
            // Bookkeeping, as in `uploadPendingPhotos` above.
            try MirrorBookkeeping.perform { try context.save() }
        }
        return failures
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
    ///
    /// Which leaves the assumption the whole of this pagination rests on, and
    /// which had never been written down anywhere: the two halves of a page
    /// are evaluated by different things. The `#Predicate`'s `uuid > cursor`
    /// is translated to SQL and compared by SQLite — **byte by byte**, its
    /// default `BINARY` collation. The sort is `.lexical`, Foundation's own
    /// character comparison. Nothing in either API promises the two agree, and
    /// a page whose filter disagrees with its own order skips rows silently.
    /// They agree here because of what a `uuid` is in this store: a
    /// `UUID().uuidString` — sixteen bytes rendered as uppercase ASCII hex and
    /// four hyphens, nothing outside 7-bit ASCII, which is where byte order
    /// and lexical order can begin to differ. `StoreMaintenance` is what keeps
    /// that true of every row, reissued ones included. An identifier from
    /// anywhere else — imported, hand-written, lowercased — would break
    /// bootstrap, blob upload and resumption at once, without an error
    /// anywhere. Corroborated empirically, on the 852-row check above; never
    /// proven.
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

            let rows = batch.map { model -> [String: MirrorValue] in
                var row = model.mirrorRow(userID: userID)
                // `edited_at` is the engine's to stamp, never `mirrorRow`'s —
                // the rule `Tests/MirrorRowSchemaTests.swift` guards, and the
                // reason this sits here rather than in the conformance. Only
                // `Activity` carries the fact locally, and only when the user
                // actually edited the row: left out, the web could never show
                // "modifié le…" for the 852 activities the bootstrap sends,
                // and catching up after the fact would mean rewriting all of
                // them. A row never edited keeps `edited_at` null, per the
                // ledger's clock decision; a later push overwrites it with
                // its outbox entry's `changedAt`.
                if let activity = model as? Activity, let editedAt = activity.editedAt {
                    row["edited_at"] = .date(editedAt)
                }
                return row
            }
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
