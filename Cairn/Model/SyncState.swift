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

    init() {}
}
