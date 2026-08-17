import Foundation
import SwiftData

/// Reading Supabase back into the store — the mirror's other direction.
///
/// Deliberately narrower than the push, and the asymmetry is the design, not
/// an unfinished corner: the Mac is the authority on everything Strava sends
/// it, and nothing but the Mac writes an activity, a lap or a weight. The web
/// writes exactly one thing, a day's note, so exactly one table is read back.
/// A pull covering all eighteen would need eighteen row-to-model conversions
/// that nothing has a use for, each one a chance to overwrite Strava's own
/// data with a stale copy of itself.
///
/// The day the web learns to record a meal, this file gains a second table
/// and nothing else changes.
extension MirrorEngine {
    /// Tables read back, and by whom they are written on the other side.
    /// Kept next to the code that walks it rather than folded into
    /// `bootstrapOrder`: that list is what goes *up*, and the two are not the
    /// same set — conflating them is how a pull would start inventing local
    /// activities out of rows the Mac itself sent.
    static let pullOrder: [String] = [
        "journal_note",
        // Les repas, dans l'ordre où ils se tiennent : la journée avant ce
        // qu'on y a mangé, pour qu'un magasin lu à moitié montre le type de
        // jour plutôt que des aliments sans budget.
        "nutrition_day", "food_entry", "meal_note",
        // La pesée, depuis que le navigateur sait l'écrire. Elle n'a pas de
        // parent : rien ne dépend de son ordre ici.
        "weight_entry",
    ]

    /// Rows per page. Smaller than `batchSize`'s 200 for no deep reason
    /// beyond the shape of the data: a page of notes is text, a page that
    /// fails costs one round trip, and a journal never changes 100 notes
    /// between two launches anyway.
    private static var pullPageSize: Int { 100 }

    /// One row of `journal_note`, as PostgREST returns it.
    ///
    /// `updated_at` and `edited_at` arrive as strings and stay strings here:
    /// Postgres writes microseconds, and `ISO8601DateFormatter` is picky
    /// enough about fractional digits that decoding them through `Date` would
    /// make the shape of the JSON a correctness question. `date(from:)` below
    /// owns that problem in one place.
    private struct JournalNoteRow: Decodable {
        let uuid: String
        let date_key_raw: String
        let text: String
        let updated_at: String
        let edited_at: String?
        let deleted_at: String?
    }

    /// Postgres timestamps, whatever precision they come back with.
    ///
    /// Two formatters, tried in order: `timestamptz` renders fractional
    /// seconds only when it has them, so `2026-08-17T09:12:00+00:00` and
    /// `2026-08-17T09:12:00.482913+00:00` are both routine, and a single
    /// `ISO8601DateFormatter` configured for one flatly refuses the other.
    static func date(from text: String) -> Date? {
        MirrorClient.iso8601.date(from: text) ?? plainISO8601.date(from: text)
    }

    /// `nonisolated(unsafe)` on the same grounds as `MirrorClient.iso8601`:
    /// never mutated after creation.
    nonisolated(unsafe) private static let plainISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Applies everything Supabase has changed since the last pull.
    ///
    /// Safe to interrupt and safe to repeat, like `bootstrap()` and `push()`,
    /// and for a related reason: the cursor advances only past rows already
    /// written to the store, and applying the same row twice reaches the same
    /// state as applying it once. What it costs to be safe is re-reading the
    /// last row of every page — see `MirrorClient.fetchChanged`'s `gte`.
    ///
    /// Never sets `lastPushAt`: this is not a push, and a pull that quietly
    /// marked the mirror as caught up would hide an outbox that never left.
    ///
    /// - Returns: how many rows were actually written to the store. The
    ///   caller needs it: `JournalStore` holds its list of notes in memory
    ///   and only rebuilds it on its own writes, so a note arriving from
    ///   another device is in the store but not on screen until someone says
    ///   so. Returning the count rather than a `Bool` so a pull that changed
    ///   nothing — the overwhelmingly common case, every launch — costs no
    ///   refetch at all.
    @discardableResult
    func pull() async throws -> Int {
        do {
            guard await client.userID != nil else { throw MirrorError.notConfigured }
            var applied = 0
            await setPhase(.pulling(done: applied))
            for table in Self.pullOrder {
                try Task.checkCancellation()
                applied += try await pullTable(table, appliedSoFar: applied)
            }
            await setPhase(.idle)
            return applied
        } catch is CancellationError {
            // Same reading as `bootstrap()` and `push()`: interrupting on
            // purpose is not a failure, and the cursor already sits wherever
            // the last applied page left it.
            await setPhase(.idle)
            throw CancellationError()
        } catch {
            await setPhase(.failed(error.localizedDescription))
            throw error
        }
    }

    private func pullTable(_ table: String, appliedSoFar: Int) async throws -> Int {
        var applied = 0
        // Advanced page by page rather than once at the end: a pull
        // interrupted after four pages must not start those four again.
        var since = cursor.lastPulledAt(for: table)
        // Combien de lignes portant exactement `since` ont déjà été lues.
        //
        // Sans lui, la lecture s'arrêtait net sur une table un peu grosse, et
        // ce n'était pas un cas rare : `now()` en Postgres est l'heure de la
        // **transaction**, si bien que les deux cents lignes d'un même lot
        // d'envoi portent toutes le même `updated_at` à la microseconde. Une
        // page entière peut donc ne contenir qu'un seul horodatage — le
        // curseur ne bouge pas, et la boucle qui s'arrêtait là laissait la
        // table figée pour toujours. Mesuré : `food_entry` bloqué à 09:12
        // pendant que les trois autres tables suivaient l'heure, parce
        // qu'elles tiennent en moins d'une page.
        var offset = 0

        while true {
            try Task.checkCancellation()
            let body = try await client.fetchChanged(
                table: table, since: since, limit: Self.pullPageSize, offset: offset
            )
            let outcome = try apply(table: table, body: body)
            applied += outcome.applied
            await setPhase(.pulling(done: appliedSoFar + applied))

            guard let newest = outcome.newestUpdatedAt else { return applied }
            // Une page incomplète est la fin des changements.
            if outcome.rowCount < Self.pullPageSize {
                cursor.setLastPulledAt(newest, for: table)
                return applied
            }
            // Le décalage compte les lignes **du dernier horodatage** déjà
            // lues, jamais les pages entières : c'est le seul repère qui
            // reprenne au bon endroit, que la page tienne dans un horodatage
            // ou en franchisse plusieurs. Raisonner par cas s'était trompé au
            // premier passage — le curseur y est nul, donc aucune égalité à
            // détecter, et la même page repartait indéfiniment.
            offset = newest == since ? offset + outcome.countAtNewest : outcome.countAtNewest
            cursor.setLastPulledAt(newest, for: table)
            since = newest
        }
    }

    private struct PullOutcome {
        var rowCount = 0
        var applied = 0
        var newestUpdatedAt: Date?
        /// Combien de lignes de cette page portent `newestUpdatedAt`.
        ///
        /// C'est ce qui permet de reprendre exactement là où la page s'arrête
        /// quand plusieurs lignes partagent un horodatage : le décalage à
        /// appliquer est ce compte, pas la taille de la page.
        var countAtNewest = 0
    }

    /// Decodes one page and writes it to the store.
    ///
    /// Synchronous, and holding its own short-lived `ModelContext`: nothing
    /// here awaits, so the context never spans a network round trip, and the
    /// notes it registers are released with it at the end of the page.
    private func apply(table: String, body: Data) throws -> PullOutcome {
        switch table {
        case "journal_note": return try applyJournalNotes(body)
        case "nutrition_day": return try applyNutritionDays(body)
        case "food_entry": return try applyFoodEntries(body)
        case "meal_note": return try applyMealNotes(body)
        case "weight_entry": return try applyWeightEntries(body)
        default:
            // `pullOrder` is a closed, hand-written list and this `switch`
            // is meant to cover every entry in it. Thrown, never asserted,
            // on the same measurement `MirrorError.unknownTable` records.
            throw MirrorError.unknownTable(table)
        }
    }

    /// Les `uuid` d'une table que l'outbox retient encore.
    ///
    /// L'arbitrage des trois tables de repas passe par là, faute d'horloge
    /// d'auteur : `FoodEntry` et ses voisines n'ont pas de `updatedAt` à
    /// comparer, là où `JournalNote` en a un. L'outbox dit exactement ce
    /// qu'il faut savoir — cette ligne a changé ici et n'est pas encore
    /// partie — et une ligne qu'elle ne nomme pas n'a rien à défendre : le
    /// serveur porte alors soit la même chose, soit ce que le téléphone a
    /// écrit depuis.
    ///
    /// Sûr parce que la lecture précède l'envoi dans `syncMirrorNow` : une
    /// modification faite ici est protégée pendant la lecture, puis poussée
    /// juste après.
    private func pendingUUIDs(table: String, in context: ModelContext) throws -> Set<String> {
        let entries = try context.fetch(
            FetchDescriptor<MirrorOutbox>(
                predicate: #Predicate { $0.table == table }
            )
        )
        return Set(entries.map(\.rowUUID))
    }

    private struct NutritionDayRow: Decodable {
        let uuid: String
        let date_key_raw: String
        let day_type_uuid: String?
        let updated_at: String
        let deleted_at: String?
    }

    private struct FoodEntryRow: Decodable {
        let uuid: String
        let date_key_raw: String
        let meal_slot_uuid: String?
        let product_code: String?
        let food_name: String
        let kcal100: Double
        let protein100: Double
        let carbs100: Double
        let fat100: Double
        let grams: Double
        let sort_order: Int
        let updated_at: String
        let deleted_at: String?
    }

    private struct WeightEntryRow: Decodable {
        let uuid: String
        let date_key_raw: String
        let weight_kg: Double
        let note: String?
        let updated_at: String
        let deleted_at: String?
    }

    private struct MealNoteRow: Decodable {
        let uuid: String
        let date_key_raw: String
        let meal_slot_uuid: String?
        let note: String
        let updated_at: String
        let deleted_at: String?
    }

    /// Décode une page, quel que soit son type de ligne.
    private func decode<Row: Decodable>(_ type: [Row].Type, from body: Data) throws -> [Row] {
        do { return try JSONDecoder().decode(type, from: body) }
        catch { throw MirrorError.decodingFailed(String(describing: error)) }
    }

    private func applyNutritionDays(_ body: Data) throws -> PullOutcome {
        let rows = try decode([NutritionDayRow].self, from: body)
        var outcome = PullOutcome(rowCount: rows.count)
        let context = ModelContext(container)
        let pending = try pendingUUIDs(table: "nutrition_day", in: context)
        var existing: [String: NutritionDay] = [:]
        for day in try context.fetch(FetchDescriptor<NutritionDay>()) {
            existing[day.uuid] = day
        }
        var types: [String: DayType] = [:]
        for type in try context.fetch(FetchDescriptor<DayType>()) { types[type.uuid] = type }

        for row in rows {
            noteNewest(row.updated_at, in: &outcome)
            guard !pending.contains(row.uuid) else { continue }

            if row.deleted_at != nil {
                guard let local = existing[row.uuid] else { continue }
                context.delete(local)
                existing[row.uuid] = nil
                outcome.applied += 1
                continue
            }
            // Le type de jour peut être absent du magasin — une ligne arrivée
            // avant celle qu'elle désigne. La journée est posée sans lui plutôt
            // que sautée : elle vaut par elle-même, et la lecture suivante
            // rattachera le type.
            let type = row.day_type_uuid.flatMap { types[$0] }
            if let local = existing[row.uuid] {
                local.dateKeyRaw = row.date_key_raw
                local.dayType = type
            } else {
                guard let dateKey = DateKey(raw: row.date_key_raw) else { continue }
                let day = NutritionDay(dateKey: dateKey, dayType: type)
                day.uuid = row.uuid
                context.insert(day)
                existing[row.uuid] = day
            }
            outcome.applied += 1
        }
        try save(context, outcome)
        return outcome
    }

    private func applyFoodEntries(_ body: Data) throws -> PullOutcome {
        let rows = try decode([FoodEntryRow].self, from: body)
        var outcome = PullOutcome(rowCount: rows.count)
        let context = ModelContext(container)
        let pending = try pendingUUIDs(table: "food_entry", in: context)
        var existing: [String: FoodEntry] = [:]
        for entry in try context.fetch(FetchDescriptor<FoodEntry>()) {
            existing[entry.uuid] = entry
        }
        var slots: [String: MealSlot] = [:]
        for slot in try context.fetch(FetchDescriptor<MealSlot>()) { slots[slot.uuid] = slot }

        for row in rows {
            noteNewest(row.updated_at, in: &outcome)
            guard !pending.contains(row.uuid) else { continue }

            if row.deleted_at != nil {
                guard let local = existing[row.uuid] else { continue }
                context.delete(local)
                existing[row.uuid] = nil
                outcome.applied += 1
                continue
            }
            let slot = row.meal_slot_uuid.flatMap { slots[$0] }
            let entry: FoodEntry
            if let local = existing[row.uuid] {
                entry = local
            } else {
                guard let dateKey = DateKey(raw: row.date_key_raw) else { continue }
                entry = FoodEntry(
                    dateKey: dateKey, mealSlot: slot, foodName: row.food_name,
                    kcal100: row.kcal100, protein100: row.protein100,
                    carbs100: row.carbs100, fat100: row.fat100, grams: row.grams,
                    sortOrder: row.sort_order, productCode: row.product_code
                )
                entry.uuid = row.uuid
                context.insert(entry)
                existing[row.uuid] = entry
            }
            entry.dateKeyRaw = row.date_key_raw
            entry.mealSlot = slot
            entry.productCode = row.product_code
            entry.foodName = row.food_name
            entry.kcal100 = row.kcal100
            entry.protein100 = row.protein100
            entry.carbs100 = row.carbs100
            entry.fat100 = row.fat100
            entry.grams = row.grams
            entry.sortOrder = row.sort_order
            outcome.applied += 1
        }
        try save(context, outcome)
        return outcome
    }

    private func applyWeightEntries(_ body: Data) throws -> PullOutcome {
        let rows = try decode([WeightEntryRow].self, from: body)
        var outcome = PullOutcome(rowCount: rows.count)
        let context = ModelContext(container)
        let pending = try pendingUUIDs(table: "weight_entry", in: context)
        var existing: [String: WeightEntry] = [:]
        for entry in try context.fetch(FetchDescriptor<WeightEntry>()) {
            existing[entry.uuid] = entry
        }

        for row in rows {
            noteNewest(row.updated_at, in: &outcome)
            guard !pending.contains(row.uuid) else { continue }

            if row.deleted_at != nil {
                guard let local = existing[row.uuid] else { continue }
                context.delete(local)
                existing[row.uuid] = nil
                outcome.applied += 1
                continue
            }
            if let local = existing[row.uuid] {
                local.dateKeyRaw = row.date_key_raw
                local.weightKg = row.weight_kg
                local.note = row.note
            } else {
                guard let dateKey = DateKey(raw: row.date_key_raw) else { continue }
                let entry = WeightEntry(
                    dateKey: dateKey, weightKg: row.weight_kg, note: row.note
                )
                entry.uuid = row.uuid
                context.insert(entry)
                existing[row.uuid] = entry
            }
            outcome.applied += 1
        }
        try save(context, outcome)
        return outcome
    }

    private func applyMealNotes(_ body: Data) throws -> PullOutcome {
        let rows = try decode([MealNoteRow].self, from: body)
        var outcome = PullOutcome(rowCount: rows.count)
        let context = ModelContext(container)
        let pending = try pendingUUIDs(table: "meal_note", in: context)
        var existing: [String: MealNote] = [:]
        for note in try context.fetch(FetchDescriptor<MealNote>()) { existing[note.uuid] = note }
        var slots: [String: MealSlot] = [:]
        for slot in try context.fetch(FetchDescriptor<MealSlot>()) { slots[slot.uuid] = slot }

        for row in rows {
            noteNewest(row.updated_at, in: &outcome)
            guard !pending.contains(row.uuid) else { continue }

            if row.deleted_at != nil {
                guard let local = existing[row.uuid] else { continue }
                context.delete(local)
                existing[row.uuid] = nil
                outcome.applied += 1
                continue
            }
            let slot = row.meal_slot_uuid.flatMap { slots[$0] }
            if let local = existing[row.uuid] {
                local.dateKeyRaw = row.date_key_raw
                local.mealSlot = slot
                local.note = row.note
            } else {
                guard let dateKey = DateKey(raw: row.date_key_raw) else { continue }
                let note = MealNote(dateKey: dateKey, mealSlot: slot, note: row.note)
                note.uuid = row.uuid
                context.insert(note)
                existing[row.uuid] = note
            }
            outcome.applied += 1
        }
        try save(context, outcome)
        return outcome
    }

    /// Le curseur avance sur toute ligne **vue**, appliquée ou non.
    ///
    /// Y compris celles que l'outbox protège : elles repartiront à l'envoi qui
    /// suit, et les retenir ferait relire la même page à chaque lancement.
    private func noteNewest(_ text: String, in outcome: inout PullOutcome) {
        guard let updated = Self.date(from: text) else { return }
        if let connu = outcome.newestUpdatedAt {
            if updated > connu {
                outcome.newestUpdatedAt = updated
                outcome.countAtNewest = 1
            } else if updated == connu {
                outcome.countAtNewest += 1
            }
        } else {
            outcome.newestUpdatedAt = updated
            outcome.countAtNewest = 1
        }
    }

    /// Exempt de l'outbox, sans quoi le Mac renverrait sous sa propre horloge
    /// ce qu'il vient de recevoir.
    private func save(_ context: ModelContext, _ outcome: PullOutcome) throws {
        guard outcome.applied > 0 else { return }
        try MirrorBookkeeping.perform { try context.save() }
    }

    private func applyJournalNotes(_ body: Data) throws -> PullOutcome {
        let rows: [JournalNoteRow]
        do {
            rows = try JSONDecoder().decode([JournalNoteRow].self, from: body)
        } catch {
            throw MirrorError.decodingFailed(String(describing: error))
        }

        var outcome = PullOutcome(rowCount: rows.count)
        let context = ModelContext(container)
        var existing: [String: JournalNote] = [:]
        for note in try context.fetch(FetchDescriptor<JournalNote>()) {
            existing[note.uuid] = note
        }

        for row in rows {
            // La même comptabilité que les trois autres tables, et non un
            // `max` écrit à part : c'est elle qui tient `countAtNewest`, dont
            // dépend la pagination à travers les horodatages identiques. Une
            // seconde version de ce calcul l'a laissé à zéro, et la lecture
            // redemandait la même page indéfiniment.
            noteNewest(row.updated_at, in: &outcome)
            // The author's clock, which is what `updatedAt` holds locally.
            // A row without one predates the column being written and cannot
            // be arbitrated against anything — left alone rather than
            // guessed at, since guessing here means overwriting a note.
            guard let editedAt = Self.date(from: row.edited_at ?? "") else { continue }

            let local = existing[row.uuid]

            if row.deleted_at != nil {
                guard let local, editedAt > local.updatedAt else { continue }
                context.delete(local)
                existing[row.uuid] = nil
                outcome.applied += 1
                continue
            }

            if let local {
                // Strictly newer, never equal: a row the Mac itself pushed
                // comes back with the very `edited_at` it sent, and applying
                // it would be a no-op that still counted as a change.
                guard editedAt > local.updatedAt else { continue }
                local.applyMirrored(text: row.text, editedAt: editedAt)
            } else {
                guard let dateKey = DateKey(raw: row.date_key_raw) else { continue }
                let note = JournalNote(dateKey: dateKey, text: row.text)
                // The remote identity, not a fresh one: a note given a new
                // `uuid` here would be pushed back as a second row, and the
                // day would end up told twice.
                note.uuid = row.uuid
                note.applyMirrored(text: row.text, editedAt: editedAt)
                context.insert(note)
                existing[row.uuid] = note
            }
            outcome.applied += 1
        }

        guard outcome.applied > 0 else { return outcome }
        // Exempt from the outbox, and this is the line that keeps the two
        // sides from talking past each other: without it `MirrorRecorder`
        // would see every applied note as a local edit and queue it for the
        // next push — the Mac sending back, under its own clock, exactly what
        // it just received.
        try MirrorBookkeeping.perform { try context.save() }
        return outcome
    }
}
