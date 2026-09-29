import Foundation
import SwiftData

/// Uploads the whole library to Supabase and keeps it there. On the pattern
/// of `SyncEngine`: an actor owning its own `ModelContext`, reporting into a
/// main-actor `MirrorProgress` the same way `SyncEngine` reports into
/// `SyncProgress`.
actor MirrorEngine {
    // Internes plutôt que privés — `private` en Swift est une portée de
    // fichier, et `MirrorPull.swift` est l'autre moitié de cet acteur, tenue à
    // part pour ne pas ajouter deux cents lignes à un fichier qui en fait déjà
    // mille. Le module reste la frontière : rien hors de Cairn ne les voit.
    let client: MirrorClient
    let container: ModelContainer
    let progress: MirrorProgress
    let cursor: MirrorBootstrapCursor
    /// L'état du chiffrement du journal, lu une fois par passe — voir
    /// `journalSealing()`. Remis à `nil` au début de chaque envoi et de chaque
    /// lecture : la phrase a pu être saisie entre deux.
    var journalSealingCache: JournalSealing?

    /// Rows per upsert, and per page fetched from SwiftData. Small enough
    /// that a batch which fails resends little on retry; large enough that
    /// 852 activities take five requests, not 852 of them.
    static let batchSize = 200

    /// Rows per blob-upload page — far smaller than `batchSize`, and
    /// deliberately so: at ~12 KB per attribute, a page of `ActivityStreams`
    /// at *this* table's own `batchSize` (200) would hold ~26 MB of blobs
    /// in memory at once (11 × 12 KB × 200). `blobBatchSize` keeps that same
    /// arithmetic under a megabyte a page instead — measured, not guessed;
    /// see the probe in the task 7 report for the resident figures this size
    /// was picked against.
    static let blobBatchSize = 5

    /// Supabase Storage bucket ids, matching `supabase/schema.sql`'s
    /// `storage.buckets` seed exactly — a typo here would upload to a bucket
    /// that silently doesn't exist rather than fail loudly.
    static let photosBucket = "photos"
    static let streamsBucket = "streams"

    /// Tables the Mac once mirrored and no longer does. An outbox entry
    /// recorded for one before the model went would name a table no `switch`
    /// below covers, and `MirrorError.unknownTable` would stop every push:
    /// they are dropped instead, unsent. Both left on 29 September 2026:
    /// `athlete`, written on every sync and read by nobody; `planned_session`,
    /// the training plan, hidden since 24 September and then removed.
    static let retiredTables: Set<String> = ["athlete", "planned_session"]

    /// The mirrored tables, parents before children — a convenience, not a
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
    /// Fixed rather than derived from the schema all the same: every name
    /// in one place, read by two `switch`es that have to cover exactly them.
    static let bootstrapOrder: [String] = [
        "gear", "day_type", "meal_slot",
        "activity", "activity_streams", "activity_photo", "lap",
        "discarded_activity",
        "nutrition_day", "food_entry", "meal_note",
        "recipe", "recipe_item", "favorite_food", "weight_entry",
        "journal_note", "journal_attachment",
        "person",
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
        journalSealingCache = nil
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
    /// Les trois objectifs nutritionnels, tels que l'appelant les a lus.
    ///
    /// Passés en argument plutôt que lus ici : ils vivent dans
    /// `UserDefaults.standard`, et un acteur du miroir qui irait les y
    /// chercher lui-même ferait exactement ce que `MirrorEngine.init`
    /// interdit à son curseur — lire les préférences du processus qui
    /// exécute les tests. `nil` quand personne ne les fournit, et alors rien
    /// n'est envoyé.
    struct NutritionTargets: Sendable, Equatable {
        var proteinG: Double
        var fatG: Double
        var fiberG: Double
        var weightGoalKg: Double
    }

    func push(nutritionTargets: NutritionTargets? = nil) async throws {
        journalSealingCache = nil
        do {
            guard let userID = await client.userID else {
                throw MirrorError.notConfigured
            }
            if let nutritionTargets {
                try await sendNutritionTargets(nutritionTargets, userID: userID)
            }
            // Before any row, for the same reason `bootstrap()` does this
            // first: a row's `storage_path` is emitted unconditionally, so a
            // photo or a stream added after the initial bootstrap must have
            // its bytes in Storage before its row goes out, not merely
            // "eventually will" once some later `bootstrap()` catches up.
            try await uploadPendingBlobs()
            try await sendNeverBootstrappedTables(userID: userID)
            // Avant de lire l'outbox, et c'est essentiel : le rapprochement
            // change des `uuid`, donc il fait naître des entrées. Les lire
            // après lui, c'est les emporter dans le même envoi.
            try await adopterLesUUIDsDeStrava()

            let outboxContext = ModelContext(container)
            let fetched = try outboxContext.fetch(FetchDescriptor<MirrorOutbox>())
            let retired = fetched.filter { Self.retiredTables.contains($0.table) }
            if !retired.isEmpty {
                for entry in retired { outboxContext.delete(entry) }
                try outboxContext.save()
            }
            let entries = fetched.filter { !Self.retiredTables.contains($0.table) }

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

    static func rowKey(table: String, uuid: String) -> String { "\(table)|\(uuid)" }

    /// Les objectifs nutritionnels, réécrits à chaque poussée.
    ///
    /// Hors outbox, seul de tout le miroir à l'être, et pour une raison
    /// précise : l'outbox est nourrie par les enregistrements SwiftData, or
    /// ces trois nombres n'en provoquent aucun — les changer dans les
    /// réglages n'écrit que dans `UserDefaults`. Les envoyer sans condition
    /// coûte une requête par synchronisation et évite de leur inventer un
    /// modèle, une migration et cinq vues à recâbler.
    ///
    /// L'`uuid` est l'identifiant de la personne : une ligne et une seule,
    /// et une clé fixe se heurterait d'un compte à l'autre.
    ///
    func sendNutritionTargets(
        _ targets: NutritionTargets, userID: String
    ) async throws {
        var row = Self.nutritionTargetRow(targets, userID: userID)
        // Apposé ici et non dans la composition, comme `pushRows` le fait pour
        // les dix-huit autres : `edited_at` appartient au moteur, jamais à la
        // ligne. Faute de mieux, c'est l'heure de l'envoi — rien ne date le
        // moment où ces réglages ont changé, et personne d'autre que le Mac ne
        // les écrit, donc il n'y a rien à arbitrer.
        row["edited_at"] = .date(Date())
        try await client.upsert(table: "nutrition_target", rows: [row])
    }

    /// La ligne elle-même, à part de son envoi.
    ///
    /// Nommée plutôt qu'écrite dans l'appel, pour la seule raison que
    /// `Tests/MirrorRowSchemaTests.swift` la compare aux colonnes de
    /// `supabase/schema.sql` comme il le fait des dix-huit `MirrorRow`. Cette
    /// table n'a pas de modèle — elle n'a donc pas la conformance qui la
    /// ferait surveiller toute seule, et une colonne ajoutée d'un côté sans
    /// l'autre passerait sans bruit.
    static func nutritionTargetRow(
        _ targets: NutritionTargets, userID: String
    ) -> [String: MirrorValue] {
        [
            "uuid": .string(userID),
            "user_id": .string(userID),
            "protein_g": .double(targets.proteinG),
            "fat_g": .double(targets.fatG),
            "fiber_g": .double(targets.fiberG),
            "weight_goal_kg": .double(targets.weightGoalKg),
        ]
    }

    /// The page size a push uses for one table's non-deletion batch — the
    /// same two constants `bootstrap()` already picked and already
    /// justified (`batchSize`, `blobBatchSize`), reused rather than
    /// reinvented. `activity_streams` and `activity_photo` carry the same
    /// inline blob columns here as they do during a bootstrap — a page of
    /// `activity_streams` at the ordinary `batchSize` would hold the same
    /// ~26 MB of blobs resident that `blobBatchSize`'s doc comment measures
    /// for `bootstrap()`, and an incremental push has no more excuse to pay
    /// that than a full one does.
    static func pushBatchSize(for table: String) -> Int {
        switch table {
        case "activity_streams", "activity_photo": blobBatchSize
        default: batchSize
        }
    }

    /// Splits a list into consecutive pieces of at most `size`. Plain
    /// `Array` chunking has no standard-library spelling; a private helper
    /// rather than pulling in anything external, on the "no new SPM
    /// dependency" constraint the whole plan holds to.
    static func chunked(_ items: [String], size: Int) -> [[String]] {
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

    /// Reprend l'`uuid` que le miroir donne déjà à une sortie Strava.
    ///
    /// Le téléphone peut importer une sortie que le Mac n'a pas encore
    /// téléchargée. Quand le Mac la télécharge à son tour, il lui donne un
    /// `uuid` neuf, et les deux mondes désignent la même sortie par deux
    /// identités : deux lignes dans le miroir, l'une avec la note écrite dans
    /// le train, l'autre avec les chiffres et la trace. La seule clé qu'ils
    /// partagent est l'identifiant Strava, et c'est par elle qu'on les
    /// recolle.
    ///
    /// **Ici et pas à l'import.** Interroger Supabase au moment où le Mac
    /// télécharge depuis Strava ferait dépendre le geste le plus fondamental
    /// de l'application d'un service tiers joignable. Ici, l'échec n'a jamais
    /// d'autre conséquence qu'un indicateur dans les réglages, et le miroir
    /// reste ce qu'il doit être : effaçable.
    ///
    /// L'entrée d'outbox est déplacée à la main, et pas laissée à
    /// l'enregistreur.
    ///
    /// Il l'aurait faite : changer l'`uuid` marque la sortie comme modifiée,
    /// et `MirrorRecorder` en tire une entrée. Mais s'appuyer là-dessus rendait
    /// le rapprochement muet dès que l'enregistreur n'est pas branché —
    /// mesuré, la sortie adoptait bien l'identité du miroir et ne repartait
    /// jamais sous elle. Une dépendance qu'on ne voit pas est une dépendance
    /// qui tombe.
    func adopterLesUUIDsDeStrava() async throws {
        let context = ModelContext(container)
        let attente = try context.fetch(
            FetchDescriptor<MirrorOutbox>(
                predicate: #Predicate { $0.table == "activity" && !$0.isDeletion }
            )
        )
        guard !attente.isEmpty else { return }

        let uuids = Set(attente.map(\.rowUUID))
        let sorties = try context.fetch(
            FetchDescriptor<Activity>(
                predicate: #Predicate { uuids.contains($0.uuid) }
            )
        )
        // Les sorties saisies à la main portent 0 : elles n'ont pas de
        // jumelle possible chez Strava, et les demander reviendrait à
        // demander « qui d'autre n'a pas d'identifiant ».
        let candidates = sorties.filter { $0.stravaID > 0 }
        guard !candidates.isEmpty else { return }

        let connus = try await client.uuidsParStravaID(candidates.map(\.stravaID))
        guard !connus.isEmpty else { return }

        // Les `uuid` déjà pris localement : reprendre celui du miroir ne doit
        // pas en écraser un autre. Le cas ne devrait pas se produire — deux
        // sorties locales pour un même identifiant Strava seraient elles-mêmes
        // un défaut, que `StoreMaintenance` répare — mais l'écrasement serait
        // silencieux, donc on s'en garde.
        let pris = Set(try context.fetch(FetchDescriptor<Activity>()).map(\.uuid))

        var adoptes = 0
        for sortie in candidates {
            guard let voulu = connus[sortie.stravaID], voulu != sortie.uuid,
                  !pris.contains(voulu)
            else { continue }
            let ancien = sortie.uuid
            sortie.uuid = voulu

            // L'ancienne entrée ne désigne plus rien : la laisser ferait une
            // page qui cherche un modèle absent, n'envoie rien et se purge.
            // Sans conséquence, mais autant ne pas la faire.
            for entree in attente where entree.rowUUID == ancien {
                context.delete(entree)
            }
            context.insert(
                MirrorOutbox(table: "activity", rowUUID: voulu, isDeletion: false)
            )
            adoptes += 1
        }
        if adoptes > 0 { try context.save() }
    }

    /// Dispatches to the concretely-typed push for one table — the same
    /// closed `switch` as `sendTable`, for the same reason: there is no way
    /// to spell "a `PersistentModel & MirrorRow` type" as a value. Returns
    /// how many outbox entries this table resolved, for `push()`'s progress
    /// count.
    func pushTable(
        _ table: String, entries: [MirrorOutbox], userID: String,
        entriesByRow: [String: [MirrorOutbox]], outboxContext: ModelContext
    ) async throws -> Int {
        switch table {
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
        case "journal_note":
            // Journal chiffré sans la clé sur ce Mac : rien ne part, et les
            // entrées restent dans l'outbox jusqu'à ce que la phrase soit saisie.
            if case .locked = try await journalSealing() { return 0 }
            return try await pushRows(JournalNote.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "journal_attachment":
            return try await pushRows(JournalAttachment.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        case "person":
            return try await pushRows(Person.self, table: table, entries: entries, userID: userID, entriesByRow: entriesByRow, outboxContext: outboxContext)
        default:
            // Every entry's `table` was written by `MirrorRecorder` from
            // `MirrorRow.mirrorTable`, and that protocol is conformed by
            // exactly the models this `switch` covers. Thrown
            // rather than asserted, for the reason `MirrorError.unknownTable`
            // records.
            //
            // It was sixteen until the journal moved into the store, and the
            // two missing cases were not a cosmetic gap: a note edited on the
            // Mac after the initial bootstrap landed here, tripped the
            // assertion in a debug build, and in release returned 0 — the
            // outbox entry neither sent nor purged, so it came back on every
            // push forever. `Tests/MirrorPushCoverageTests.swift` now derives
            // the expectation from `bootstrapOrder` rather than from a
            // second hand-written list.
            throw MirrorError.unknownTable(table)
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
    /// ## Pourquoi les lectures par `uuid` filtrent en Swift, ici et deux fois
    /// plus bas
    ///
    /// SwiftData retrouve la propriété derrière un `keyPath` en comparant des
    /// `keyPath`, et ceux d'un `@Model` sont *calculés* : la comparaison porte
    /// sur l'adresse des accesseurs. Formé dans une fonction générique qu'une
    /// compilation optimisée spécialise, le `keyPath` n'est plus celui que le
    /// schéma tient, la recherche échoue, et SwiftData s'arrête net :
    ///
    ///     SwiftData/DataUtilities.swift:85: Fatal error: Couldn't find
    ///     \Athlete.<computed 0x104b320e8 (String)> on Athlete with fields
    ///     [PropertyMetadata(name: "uuid", keypath: \Athlete.<computed
    ///     0x1049b7b5c (String)>, …)]
    ///
    /// Mesuré le 31 août 2026, et pas déduit : en Release l'application mourait
    /// à chaque synchronisation, sur la ligne de l'athlète, la seule en attente
    /// dans l'outbox. En Debug rien ne se voit — sans spécialisation les deux
    /// `keyPath` sont le même objet. Un `#Predicate` écrit sur le type concret
    /// passe dans les deux cas : c'est la généricité qui décide, l'optimiseur
    /// ne fait que la révéler. `propertiesToFetch` de `StoreMaintenance` ne
    /// souffre pas du même mal, et pour la même raison : son `keyPath` lui est
    /// donné tout formé par un appelant qui nomme le modèle.
    ///
    /// D'où ce parti : lire la table et filtrer en Swift. Le prix est une
    /// lecture de table par page envoyée, sur des lignes plates — les blobs
    /// sont en stockage externe et ne suivent pas, ce qui laisse intacte
    /// l'arithmétique de `blobBatchSize`. Garder le filtre en SQL demanderait
    /// un `#Predicate` écrit sur chacune des vingt conformances, soit soixante
    /// lignes qu'aucun compilateur ne saurait tenir à jour ; à reprendre le
    /// jour où une table sera assez grosse pour que la lecture se sente.
    func pushRows<Model: PersistentModel & MirrorRow>(
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
                // Le filtre en Swift plutôt qu'en SQL : contournement, pas
                // choix — voir la note en tête de cette fonction.
                let models = try pageContext.fetch(FetchDescriptor<Model>())
                    .filter { pageUUIDs.contains($0.uuid) }
                // A row named by an entry but absent from the store —
                // created and deleted before the recorder ever saw it as a
                // deletion — has nothing left to send; the ones that do
                // exist still go.
                if !models.isEmpty {
                    let rows = try models.map { model -> [String: MirrorValue] in
                        var row = model.mirrorRow(userID: userID)
                        if let changedAt = changedAtByUUID[model.uuid] {
                            row["edited_at"] = .date(changedAt)
                        }
                        try sealIfJournal(&row, table: table)
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
    func purge(
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

    func setPhase(_ phase: MirrorPhase) async {
        await MainActor.run { progress.phase = phase }
    }

    func finish() async {
        let now = Date()
        cursor.setLastPushAt(now)
        await MainActor.run {
            progress.phase = .idle
            progress.lastPushAt = now
        }
    }
}
