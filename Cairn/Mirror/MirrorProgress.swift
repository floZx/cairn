import Foundation
import Observation

/// Phases a bootstrap or a push can be in. `MirrorEngine` reports into
/// `MirrorProgress` from its own actor; the settings screen reads it back on
/// the main actor. Same split as `SyncPhase`/`SyncProgress`, on purpose: this
/// is the second time the app needs "background actor talks to an
/// `@Observable` on the main actor", and it is not a pattern worth inventing
/// twice.
enum MirrorPhase: Sendable, Equatable {
    case idle
    case bootstrapping(table: String, done: Int, total: Int)
    case pushing(done: Int, total: Int)
    case failed(String)
}

/// UI-facing mirror state. Lives on the main actor so views can observe it
/// directly; `MirrorEngine` pushes updates into it with `MainActor.run`,
/// exactly as `SyncEngine` does for `SyncProgress`.
@MainActor
@Observable
final class MirrorProgress {
    var phase: MirrorPhase = .idle
    /// Set at the end of a successful bootstrap or push — whichever last
    /// finished cleanly. `SyncProgress.lastRunAt` plays the same role for
    /// Strava.
    var lastPushAt: Date?

    /// Whether a bootstrap or a push is under way — `SyncProgress.isRunning`'s
    /// counterpart, needed for the same reason: a settings screen has to
    /// disable its own "amorcer" button while one is already running rather
    /// than let a second overlap the first.
    var isRunning: Bool {
        switch phase {
        case .idle, .failed: false
        case .bootstrapping, .pushing: true
        }
    }

    /// What to show, in words, never silent — the same rule `SyncProgress`
    /// follows and for the same reason: a mirror never configured and one
    /// that is merely idle must not read the same way, or "nothing to report"
    /// becomes indistinguishable from "nothing has ever happened".
    var statusText: String {
        switch phase {
        case .idle:
            lastPushAt.map { "Dernière synchro \(Format.shortDate($0))" }
                ?? "Jamais synchronisé"
        case let .bootstrapping(table, done, total):
            "Amorçage… \(table) \(done)/\(total)"
        case let .pushing(done, total):
            "Envoi… \(done)/\(total)"
        case let .failed(message):
            "Échec : \(message)"
        }
    }
}
