import Foundation
import SwiftData

/// The one place for everything that has to happen once to an existing store.
enum StoreMaintenance {
    /// One model's repair, tied to the schema entity it targets.
    ///
    /// The tie is what makes the guarantee checkable without a second
    /// hand-written list: `Tests/StoreMaintenanceTests.swift` compares
    /// `entityName` across every entry here against every entity
    /// `AppModelContainer.schema` reports as carrying a `uuid` property,
    /// read reflectively off `Schema.Entity.storedProperties` rather than
    /// copied out by hand. A model added to the schema with a `uuid` and
    /// never wired up below shows up there as a name present on one side and
    /// missing on the other — red, not a silent gap that only a restored
    /// backup would ever reveal.
    struct UUIDRepair {
        let entityName: String
        let reissue: (ModelContext) throws -> Int
    }

    /// Builds one `UUIDRepair`, reading its entity name off `Schema` itself
    /// rather than repeating the class name as a string — the one place a
    /// typo here could otherwise separate the two sides of the guarantee.
    private static func repair<Model: PersistentModel>(
        _ type: Model.Type, _ uuid: ReferenceWritableKeyPath<Model, String>
    ) -> UUIDRepair {
        UUIDRepair(entityName: Schema.entityName(for: type)) {
            try reissueDuplicateUUIDs(uuid, in: $0)
        }
    }

    /// Every uuid-bearing model in `AppModelContainer.schema` — the sixteen
    /// that cross to the mirror, and the journal's two local ones.
    ///
    /// A SwiftData property default is a single value in the managed model,
    /// and a lightweight migration applied it to every existing row: the
    /// user's 840 activities came out of it sharing one uuid — measured, not
    /// supposed. Views key off that identity.
    ///
    /// All sixteen mirrored models, not `Activity` alone: `uuid` reached the
    /// other fifteen with the mirror, and `AppModelContainer.make()` has no
    /// `MigrationPlan`, so it is the very same lightweight migration that
    /// applies them — 5 672 laps, 852 stream rows, 343 photos and 828 food
    /// entries each sharing one value on the real library. Nothing above
    /// tolerates that: `MirrorEngine` pages by `uuid > cursor` and would call
    /// a table finished after its first page, `blobStoragePath` names
    /// Storage objects by `uuid` and would overwrite one object per table,
    /// and an upsert carrying the same key twice is a hard `21000` from
    /// Postgres.
    ///
    /// `JournalNote` and `JournalAttachment` never reach `MirrorEngine` —
    /// this slice is local only — but the SwiftData mechanism that
    /// duplicates `uuid` across existing rows does not know that, and a
    /// store restored from a future backup would carry the exact same
    /// duplicated identity on them. Views key off `JournalNote.uuid` the
    /// same way they key off `Activity.uuid`, so they get the same repair.
    ///
    /// `nonisolated(unsafe)`: each `reissue` closure captures a
    /// `ReferenceWritableKeyPath`, which the compiler does not treat as
    /// `Sendable` for an arbitrary `Model`, so a `@Sendable` closure type
    /// here would not type-check. The array itself is never mutated after
    /// this initializer runs — a `let`, built once — which is exactly the
    /// case that annotation is for.
    nonisolated(unsafe) static let uuidRepairs: [UUIDRepair] = [
        repair(Activity.self, \.uuid),
        repair(ActivityStreams.self, \.uuid),
        repair(ActivityPhoto.self, \.uuid),
        repair(Lap.self, \.uuid),
        repair(Gear.self, \.uuid),
        repair(DiscardedActivity.self, \.uuid),
        repair(DayType.self, \.uuid),
        repair(MealSlot.self, \.uuid),
        repair(NutritionDay.self, \.uuid),
        repair(FoodEntry.self, \.uuid),
        repair(MealNote.self, \.uuid),
        repair(Recipe.self, \.uuid),
        repair(RecipeItem.self, \.uuid),
        repair(FavoriteFood.self, \.uuid),
        repair(WeightEntry.self, \.uuid),
        repair(JournalNote.self, \.uuid),
        repair(JournalAttachment.self, \.uuid),
        repair(PlannedSession.self, \.uuid),
        repair(Person.self, \.uuid),
    ]

    /// Rebuilds the journal's picture cache, then runs every repair in
    /// `uuidRepairs`, then folds the days written twice.
    ///
    /// Returns how many rows the *repairs* changed. Returning this count is
    /// what makes the repairs testable and their idempotence checkable.
    ///
    /// Runs on every launch, so the pass that finds nothing to do has to stay
    /// cheap: `reissueDuplicateUUIDs` fetches `uuid` and nothing else, which
    /// matters for the tables carrying blobs inline (`ActivityStreams`'
    /// eleven `Data?`, `ActivityPhoto.data`, `JournalAttachment.data`) —
    /// reading them in full every launch would cost hundreds of megabytes
    /// resident for a scan that changes nothing.
    ///
    /// - Parameter cacheDirectory: where `JournalAttachmentCache.rebuild`
    ///   materialises the journal's images. No default value, deliberately:
    ///   `materialise` and `rebuild` both had theirs removed for the reason
    ///   their own doc comments give, and a default here once had the suite
    ///   writing `un.jpg` and `deux.jpg` into the application's real cache
    ///   folder — measured, not supposed.
    @discardableResult
    static func run(_ context: ModelContext, cacheDirectory: URL) throws -> Int {
        // Its failures stay silent: this folder is derived and
        // reconstructible, so a disk error here costs a relaunch, not a note.
        try? JournalAttachmentCache.rebuild(context, vaultRoot: cacheDirectory)

        var changed = 0

        for repair in uuidRepairs {
            changed += try repair.reissue(context)
        }

        // Hors du compte rendu : une journée
        // racontée deux fois n'est pas une identité à réparer, c'est un texte
        // à recoller. Les bases d'avant le correctif en portent — la règle
        // vient d'arriver côté miroir, elle n'a pas pu défaire ce qui était
        // déjà là. Voir `JournalNoteWrite.foldDuplicateDays`.
        let recolles = JournalNoteWrite.foldDuplicateDays(in: context)

        guard changed > 0 || recolles > 0 else { return 0 }
        try context.save()
        return changed
    }

    /// One model's pass: every row keeping an identity nobody else in its own
    /// table holds. Returns how many were reissued.
    ///
    /// Uniqueness is per model, not across the store: `uuid` is each
    /// mirrored table's own primary key in `supabase/schema.sql`
    /// (`JournalNote` and `JournalAttachment` carry no such row at all, only
    /// the same local convention), and the two Storage paths built from a
    /// `uuid` live in different buckets, so two tables sharing a value
    /// collides with nothing.
    ///
    /// Takes a writable key path rather than reading `MirrorRow.uuid`, which
    /// is get-only and stays that way — a mirrored row's identity is not
    /// something the mirror itself may rewrite. Not constrained to
    /// `MirrorRow`: `JournalNote` and `JournalAttachment` need the exact same
    /// repair without crossing the mirror. What pins the set of models
    /// repaired is `uuidRepairs` above, checked against the schema by
    /// `Tests/StoreMaintenanceTests.swift` — not a type constraint here.
    ///
    /// Never paged: pagination by `uuid` is exactly what a duplicated `uuid`
    /// breaks — that is the bug being repaired here — and pagination by
    /// position would shift under a row whose uuid this pass has just changed.
    /// The whole table at once, with `propertiesToFetch` keeping the scan to
    /// the one column, is the shape that cannot be wrong.
    private static func reissueDuplicateUUIDs<Model: PersistentModel>(
        _ uuid: ReferenceWritableKeyPath<Model, String>, in context: ModelContext
    ) throws -> Int {
        var descriptor = FetchDescriptor<Model>()
        // Only the identity column: a launch that repairs nothing must not
        // pull `ActivityStreams`' eleven inline blobs into memory to find that
        // out. A row this pass does write to faults the rest of itself in on
        // its own, which is the price of repairing it and nothing more.
        descriptor.propertiesToFetch = [uuid]
        let rows = try context.fetch(descriptor)

        var seen: Set<String> = []
        var changed = 0
        for row in rows {
            // First claimant of a duplicated uuid keeps it; the rest are reissued.
            // Reassigning them all would churn identities that are already fine.
            if row[keyPath: uuid].isEmpty || seen.contains(row[keyPath: uuid]) {
                row[keyPath: uuid] = UUID().uuidString
                changed += 1
            }
            seen.insert(row[keyPath: uuid])
        }
        return changed
    }
}
