import Foundation
import SwiftData

/// A Strava activity the user deleted, kept so it stays deleted.
///
/// The journal is the reference, so a deletion is a decision — and a full
/// resync must not undo it. Only the Strava identifier matters for that; the
/// name is kept so the settings screen can say what was discarded, a bare
/// number being impossible to review.
@Model
final class DiscardedActivity {
    #Index<DiscardedActivity>([\.stravaID])

    var stravaID: Int64 = 0
    var name: String = ""
    var discardedAt: Date = Date.distantPast
    /// The discarded activity's own start date, so `restore` can put the sync
    /// cursor back behind it. Without this the promise made in the settings —
    /// that reinstating an activity lets it come back on the next sync — holds
    /// only for the most recent ones: the cursor has already moved past the rest,
    /// and only a full resync would reach them, at the cost of re-fetching every
    /// track.
    var startDate: Date = Date.distantPast

    init(
        stravaID: Int64, name: String, discardedAt: Date = Date(),
        startDate: Date = Date.distantPast
    ) {
        self.stravaID = stravaID
        self.name = name
        self.discardedAt = discardedAt
        self.startDate = startDate
    }
}
