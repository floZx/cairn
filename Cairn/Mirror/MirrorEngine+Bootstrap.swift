import Foundation
import SwiftData

// Sending whole tables: the first bootstrap, and any table it never reached.
extension MirrorEngine {
    /// Sends, in full, any table that has never been bootstrapped.
    ///
    /// A table added to `bootstrapOrder` after the mirror was first set up
    /// has no cursor, and the outbox has nothing to say about it either: the
    /// recorder only ever filed the models that conformed `MirrorRow` at the
    /// time they were saved. `journal_note` and `journal_attachment` arrived
    /// exactly that way — the notes were already in the store, written before
    /// they mirrored — and the result was a push that ran clean and sent
    /// nothing, twice, with no way to tell from the settings screen that two
    /// tables were simply never in the conversation.
    ///
    /// Cheap to leave in: `lastUUID(for:)` is a `UserDefaults` read per table,
    /// and once a table has been through this it never comes back. That makes
    /// the hand-started bootstrap a repair tool again rather than a step
    /// somebody has to know to take after every schema addition — there are
    /// three more tranches of those coming.
    /// Only once the mirror is *established*, which is the whole distinction:
    /// on a mirror nobody has bootstrapped yet, every table lacks a cursor,
    /// and sending them all would turn the launch push into a silent 290 MB
    /// upload the user never asked for. "Some table has a cursor" is what
    /// separates a schema addition from a first run — and the first run stays
    /// what it was, an explicit « Lancer l'amorçage ».
    func sendNeverBootstrappedTables(userID: String) async throws {
        let established = Self.bootstrapOrder.contains { cursor.lastUUID(for: $0) != nil }
        guard established else { return }

        for table in Self.bootstrapOrder where cursor.lastUUID(for: table) == nil {
            try Task.checkCancellation()
            try await sendTable(table, userID: userID)
        }
    }

    /// Dispatches to the concretely-typed fetch for one table. A `switch`
    /// over a fixed, closed list rather than a lookup table, because there is
    /// no way to spell "a `PersistentModel & MirrorRow` type" as a value in
    /// Swift — the type has to appear in source for the compiler to see it.
    func sendTable(_ table: String, userID: String) async throws {
        switch table {
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
        case "journal_note":
            // Le curseur ne bouge pas : la table reprendra entière une fois
            // la phrase saisie. Demandé seulement s'il y a des notes à envoyer.
            if try ModelContext(container).fetchCount(FetchDescriptor<JournalNote>()) > 0,
               case .locked = try await journalSealing() { return }
            try await sendBatches(JournalNote.self, table: table, userID: userID)
        case "journal_attachment":
            try await sendBatches(JournalAttachment.self, table: table, userID: userID)
        case "planned_session":
            try await sendBatches(PlannedSession.self, table: table, userID: userID)
        case "person": try await sendBatches(Person.self, table: table, userID: userID)
        default:
            // `bootstrapOrder` is a closed, hand-written list and this
            // `switch` is meant to cover every entry in it. Thrown rather
            // than asserted — see `MirrorError.unknownTable`, which carries
            // the measurement: an assertion here made the guard test crash
            // the runner, and a crashed run reports as a pass.
            throw MirrorError.unknownTable(table)
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
    func sendBatches<Model: PersistentModel & MirrorRow>(
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
            // La page se découpe en Swift : le prédicat comme le tri
            // passaient par un `keyPath` formé ici, dans une fonction
            // générique — voir la note en tête de `pushRows`. L'ordre ne
            // change pas de sens au passage : `uuidString` n'est fait que de
            // chiffres hexadécimaux et de tirets, où l'ordre d'octets de
            // Swift et le `.lexical` d'avant se rangent pareil. Et les deux
            // moitiés — la borne et le tri — sont maintenant du même côté,
            // là où l'une lisait la collation de SQLite et l'autre non.
            let lastUUID = cursor.lastUUID(for: table)
            let batch = Array(
                try pageContext.fetch(FetchDescriptor<Model>())
                    .filter { ligne in lastUUID.map { ligne.uuid > $0 } ?? true }
                    .sorted { $0.uuid < $1.uuid }
                    .prefix(Self.batchSize)
            )
            if batch.isEmpty { break }

            let rows = try batch.map { model -> [String: MirrorValue] in
                var row = model.mirrorRow(userID: userID)
                // `edited_at` is the engine's to stamp, never `mirrorRow`'s —
                // the rule `Tests/MirrorRowSchemaTests.swift` guards, and the
                // reason this sits here rather than in the conformance. Only
                // `Activity` carries the fact locally: left out, the web
                // could never show "modifié le…" for the 852 activities the
                // bootstrap sends, and catching up after the fact would mean
                // rewriting all of them. The column is set for every
                // `Activity` row, never merely skipped when unedited — a
                // single POST carries up to `batchSize` rows, and PostgREST
                // requires every object in the array to share the same keys.
                // A row never edited encodes `.null`, per `MirrorRow`'s own
                // invariant; a later push overwrites it with its outbox
                // entry's `changedAt`.
                if let activity = model as? Activity {
                    row["edited_at"] = activity.editedAt.map(MirrorValue.date) ?? .null
                }
                try sealIfJournal(&row, table: table)
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

    /// How many of this table's rows the cursor already accounts for — pour
    /// le seul chiffre d'avancement montré pendant la remontée initiale.
    ///
    /// C'était un `fetchCount`, qui ne ramenait aucune ligne. Il compte
    /// maintenant des lignes lues, faute de pouvoir poser le prédicat — voir
    /// la note en tête de `pushRows`. Le prix est une lecture de la table par
    /// table remontée, une seule fois, et les blobs n'en sont pas : ils sont
    /// en stockage externe et ne se chargent qu'à la lecture d'un octet.
    func alreadySentCount<Model: PersistentModel & MirrorRow>(
        _ type: Model.Type, table: String
    ) throws -> Int {
        guard let lastUUID = cursor.lastUUID(for: table) else { return 0 }
        return try ModelContext(container).fetch(FetchDescriptor<Model>())
            .filter { $0.uuid <= lastUUID }
            .count
    }
}
