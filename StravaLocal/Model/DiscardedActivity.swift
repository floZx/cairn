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

    init(stravaID: Int64, name: String, discardedAt: Date = Date()) {
        self.stravaID = stravaID
        self.name = name
        self.discardedAt = discardedAt
    }
}
