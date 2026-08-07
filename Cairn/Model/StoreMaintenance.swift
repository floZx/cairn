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

        guard changed > 0 else { return 0 }
        try context.save()
        return changed
    }
}
