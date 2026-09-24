import Foundation
import SwiftData

/// Single-row record holding everything needed to resume a sync. Progress lives
/// in the database, not in memory, so quitting the app or exhausting the API
/// quota interrupts a sync without losing it.
@Model
final class SyncState {
    /// `after` cursor for the summary endpoint: epoch seconds of the most
    /// recent activity already imported.
    var lastSummaryEpoch: Int = 0
    /// Strava IDs of activities whose streams are still missing.
    var pendingStreamIDs: [Int64] = []
    var lastRunAt: Date?
    var lastErrorMessage: String?
    var isInitialImportDone: Bool = false
    /// Set once every Strava activity has been queued for a second look at
    /// its detail, for the private note that was not read before September
    /// 2026. See `SyncEngine.requestPrivateNotesOnce()`.
    ///
    /// A second name for a second pass: the first (`privateNotesRequested`,
    /// gone) kept the private note apart, and the ten activities it reached
    /// must be read again to fold theirs into the note.
    var privateNotesMerged: Bool = false

    init() {}
}
