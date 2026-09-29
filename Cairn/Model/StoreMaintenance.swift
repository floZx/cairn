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
    /// `Activity` first, because `linkPhotosToTheirActivity` in `run` reads
    /// the uuid this pass may have just reissued.
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
        repair(Athlete.self, \.uuid),
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

    /// Runs the journal's one-time recovery, then every repair in
    /// `uuidRepairs`, then the one repair that is not about `uuid` at all.
    ///
    /// The recovery cannot take the repairs down with it, and that is the
    /// point of `recoverJournal` swallowing its own failures rather than
    /// throwing them here: it is allowed to fail and retry — a folder on an
    /// unmounted volume, a path the user has since reorganised — but a
    /// journal folder nobody can read any more must not mean eighteen `uuid`
    /// repairs, `linkPhotosToTheirActivity` and the attachment cache never
    /// running again on any launch, forever. The marker is never set on a
    /// failed recovery, so "forever" is literal: that is exactly the shape
    /// this used to have, with `try recoverJournal` as the first statement of
    /// this function and no `catch` anywhere.
    ///
    /// Returns how many rows the *repairs* changed — the recovery's own count
    /// is a different thing (files, not repaired rows) and is not folded into
    /// this one; see `recoverJournal(_:defaults:cacheDirectory:)` for where its own report
    /// goes. Returning this count is what makes the repairs testable and
    /// their idempotence checkable.
    ///
    /// Runs on every launch, so the pass that finds nothing to do has to stay
    /// cheap: `reissueDuplicateUUIDs` fetches `uuid` and nothing else, which
    /// matters for the tables carrying blobs inline (`ActivityStreams`'
    /// eleven `Data?`, `ActivityPhoto.data`, `JournalAttachment.data`) —
    /// reading them in full every launch would cost hundreds of megabytes
    /// resident for a scan that changes nothing.
    ///
    /// - Parameter defaults: where the recovery reads the folder it used to
    ///   live in (`JournalSettings.folderPathKey`) and records that it ran
    ///   (`JournalSettings.importDoneKey`). Defaults to `.standard` for the
    ///   application's one real call site (`CairnApp.init`) alone — every
    ///   test passes a throwaway suite of its own, exactly the reasoning
    ///   `MirrorEngine.init`'s own `cursor:` parameter gives at length: a
    ///   test that let this default stand would read and write this Mac's
    ///   real journal folder path and its real recovery marker.
    /// - Parameter cacheDirectory: where `JournalAttachmentCache.rebuild`
    ///   materialises the journal's images. No default value, deliberately,
    ///   and for the third time in this repository: `materialise` and
    ///   `rebuild` both had theirs removed for the reason their own doc
    ///   comments give, and `MirrorEngine.init`'s `cursor:` before them. This
    ///   function kept naming `JournalAttachmentCache.vaultRoot` itself even
    ///   after `defaults:` was opened up, so the suite went on writing
    ///   `un.jpg` and `deux.jpg` into the application's real cache folder —
    ///   measured, not supposed.
    @discardableResult
    static func run(
        _ context: ModelContext, cacheDirectory: URL, defaults: UserDefaults = .standard
    ) throws -> Int {
        recoverJournal(context, defaults: defaults, cacheDirectory: cacheDirectory)

        var changed = 0

        for repair in uuidRepairs {
            changed += try repair.reissue(context)
        }

        changed += try linkPhotosToTheirActivity(context)

        // Hors du compte rendu, comme la récupération du journal : une journée
        // racontée deux fois n'est pas une identité à réparer, c'est un texte
        // à recoller. Les bases d'avant le correctif en portent — la règle
        // vient d'arriver côté miroir, elle n'a pas pu défaire ce qui était
        // déjà là. Voir `JournalNoteWrite.foldDuplicateDays`.
        let recolles = JournalNoteWrite.foldDuplicateDays(in: context)

        guard changed > 0 || recolles > 0 else { return 0 }
        try context.save()
        return changed
    }

    /// The journal folder's one-time recovery, and the cache that depends on
    /// what it just inserted.
    ///
    /// First, always: `JournalAttachmentCache.rebuild` can only materialise
    /// what the store already holds, and on the very first launch after this
    /// slice ships, that is nothing at all until the recovery has run.
    ///
    /// Nothing here folds into `run`'s own return value — a row `uuidRepairs`
    /// changed and a file the recovery imported are not the same kind of
    /// count, and `Tests/StoreMaintenanceTests.swift` holds `run`'s count to
    /// the repairs alone.
    ///
    /// The recovery's unreadable files, if any, are handed to `JournalNotice`
    /// and the one sentence it produces is written to
    /// `JournalSettings.importNoticeKey` — the only trace the reader gets
    /// that a note deserves a second look, since the recovery itself runs
    /// once and is gone by the time anyone could open the journal to notice.
    ///
    /// Throws nothing, deliberately: see `run`'s own doc comment on what a
    /// throw from here used to cost. A recovery that fails leaves its marker
    /// unset and retries at the next launch — that is the specification —
    /// and `JournalImport.runIfNeeded` has already rolled its own context
    /// back by the time the error arrives here, so there is no half-inserted
    /// journal for the repairs below to save.
    ///
    /// A failure gets the same signalling as an unreadable file, through the
    /// same key: without it the reader is left with an empty journal, no
    /// message, and — since the folder picker went with the folder — no way
    /// to work out that a stale path is the reason.
    private static func recoverJournal(
        _ context: ModelContext, defaults: UserDefaults, cacheDirectory: URL
    ) {
        let folderPath = defaults.string(forKey: JournalSettings.folderPathKey)
        do {
            if let outcome = try JournalImport.runIfNeeded(
                context, folderPath: folderPath, defaults: defaults
            ), let message = JournalNotice.notice(unreadable: outcome.unreadable)?.message {
                defaults.set(message, forKey: JournalSettings.importNoticeKey)
            }
        } catch {
            defaults.set(
                JournalNotice.notice(recoveryFailure: folderPath).message,
                forKey: JournalSettings.importNoticeKey
            )
        }
        // Rebuilt even when the recovery above failed, and outside its `do`
        // for that reason alone: the cache materialises what the store
        // *already* holds, which on every launch after the first is the whole
        // journal — a folder that has gone stale says nothing about the notes
        // recovered from it a year ago. Its own failures stay silent: this
        // folder is derived and reconstructible, so a disk error here costs a
        // relaunch, not a note, and the sentence written above is about the
        // folder rather than about the cache.
        try? JournalAttachmentCache.rebuild(context, vaultRoot: cacheDirectory)
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

    /// Fills in `ActivityPhoto.activityUUID` for photos stored before it existed.
    ///
    /// Without it those photos are invisible: the pane finds them by that field
    /// rather than through the relationship, and the sync will not fetch them
    /// again — `photosFetchedAt` is already set on their activity.
    private static func linkPhotosToTheirActivity(_ context: ModelContext) throws -> Int {
        // Compared to the empty string rather than asked `isEmpty`: the
        // predicate engine translates the comparison and silently matches
        // nothing for the property access, which is how this repair first ran
        // and repaired zero rows.
        let orphans = try context.fetch(
            FetchDescriptor<ActivityPhoto>(
                predicate: #Predicate { $0.activityUUID == "" }
            )
        )
        var changed = 0
        for photo in orphans {
            guard let uuid = photo.activity?.uuid, !uuid.isEmpty else { continue }
            photo.activityUUID = uuid
            changed += 1
        }
        return changed
    }
}
