import Foundation
import SwiftData

/// The one place for everything that has to happen once to an existing store.
enum StoreMaintenance {
    /// Gives every activity an identity of its own.
    ///
    /// Two cases, and the second is why this does not merely look for empty
    /// strings. A SwiftData property default is a single value in the managed
    /// model, and a lightweight migration applied it to every existing row: the
    /// user's 840 activities came out of it sharing one uuid — measured, not
    /// supposed. Views key off that identity.
    ///
    /// Returns how many rows were changed, which is what makes it testable and
    /// its idempotence checkable.
    @discardableResult
    static func run(_ context: ModelContext) throws -> Int {
        let activities = try context.fetch(FetchDescriptor<Activity>())
        var seen: Set<String> = []
        var changed = 0

        for activity in activities {
            // First claimant of a duplicated uuid keeps it; the rest are reissued.
            // Reassigning them all would churn identities that are already fine.
            if activity.uuid.isEmpty || seen.contains(activity.uuid) {
                activity.uuid = UUID().uuidString
                changed += 1
            }
            seen.insert(activity.uuid)
        }

        changed += try linkPhotosToTheirActivity(context)

        guard changed > 0 else { return 0 }
        try context.save()
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
