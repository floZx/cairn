import Foundation
import SwiftData

/// The one place for everything that has to happen once to an existing store.
enum StoreMaintenance {
    /// Gives every uuid-bearing row an identity of its own — the sixteen
    /// models that cross to the mirror, and the journal's two local ones.
    ///
    /// Two cases, and the second is why this does not merely look for empty
    /// strings. A SwiftData property default is a single value in the managed
    /// model, and a lightweight migration applied it to every existing row: the
    /// user's 840 activities came out of it sharing one uuid — measured, not
    /// supposed. Views key off that identity.
    ///
    /// All sixteen mirrored models, not `Activity` alone: `uuid` reached the
    /// other fifteen with the mirror, and `AppModelContainer.make()` has no
    /// `MigrationPlan`, so it is the very same lightweight migration that
    /// applies them — 5 672 laps, 852 stream rows, 343 photos and 828 food
    /// entries each sharing one value on the real library. Nothing above
    /// tolerates that: `MirrorEngine` pages by `uuid > cursor` and would call a
    /// table finished after its first page, `blobStoragePath` names Storage
    /// objects by `uuid` and would overwrite one object per table, and an
    /// upsert carrying the same key twice is a hard `21000` from Postgres.
    ///
    /// `JournalNote` and `JournalAttachment` never reach `MirrorEngine` — this
    /// slice is local only — but the SwiftData mechanism that duplicates
    /// `uuid` across existing rows does not know that, and a store restored
    /// from a future backup would carry the exact same duplicated identity on
    /// them. Views key off `JournalNote.uuid` the same way they key off
    /// `Activity.uuid`, so they get the same repair.
    ///
    /// Returns how many rows were changed, which is what makes it testable and
    /// its idempotence checkable.
    ///
    /// Runs on every launch, so the pass that finds nothing to do has to stay
    /// cheap: `reissueDuplicateUUIDs` fetches `uuid` and nothing else, which
    /// matters for the tables carrying blobs inline (`ActivityStreams`'
    /// eleven `Data?`, `ActivityPhoto.data`, `JournalAttachment.data`) —
    /// reading them in full every launch would cost hundreds of megabytes
    /// resident for a scan that changes nothing.
    @discardableResult
    static func run(_ context: ModelContext) throws -> Int {
        var changed = 0

        // The sixteen models that cross — `MirrorRow`'s own list. Nothing
        // pins this call list to it any more (see `reissueDuplicateUUIDs`
        // below), so it is this explicit enumeration, not a type constraint,
        // that has to stay complete. `Activity` first, because
        // `linkPhotosToTheirActivity` below reads the uuid this pass may
        // have just reissued.
        changed += try reissueDuplicateUUIDs(\Activity.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\ActivityStreams.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\ActivityPhoto.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\Lap.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\Gear.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\Athlete.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\DiscardedActivity.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\DayType.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\MealSlot.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\NutritionDay.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\FoodEntry.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\MealNote.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\Recipe.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\RecipeItem.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\FavoriteFood.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\WeightEntry.uuid, in: context)

        // The two that do not cross the mirror at all. Same repair, same
        // reason: a restored backup does not know it is exempt.
        changed += try reissueDuplicateUUIDs(\JournalNote.uuid, in: context)
        changed += try reissueDuplicateUUIDs(\JournalAttachment.uuid, in: context)

        changed += try linkPhotosToTheirActivity(context)

        guard changed > 0 else { return 0 }
        try context.save()
        return changed
    }

    /// One model's pass: every row keeping an identity nobody else in its own
    /// table holds. Returns how many were reissued.
    ///
    /// Uniqueness is per model, not across the store: `uuid` is each mirrored
    /// table's own primary key in `supabase/schema.sql` (`JournalNote` and
    /// `JournalAttachment` carry no such row at all, only the same local
    /// convention), and the two Storage paths built from a `uuid` live in
    /// different buckets, so two tables sharing a value collides with nothing.
    ///
    /// Takes a writable key path rather than reading `MirrorRow.uuid`, which
    /// is get-only and stays that way — a mirrored row's identity is not
    /// something the mirror itself may rewrite. No longer constrained to
    /// `MirrorRow`: `JournalNote` and `JournalAttachment` need the exact same
    /// repair without crossing the mirror, so the constraint that used to pin
    /// this to mirrored models only would have excluded them. What actually
    /// pins the set of models repaired is the explicit call list in `run`
    /// above, not a type constraint here.
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
