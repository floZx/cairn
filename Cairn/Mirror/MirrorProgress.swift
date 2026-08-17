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
    /// `uploadPendingBlobs()` in flight — before any row, always: `bootstrap()`
    /// and `push()` both call it first, so a photo or a stream never
    /// announces a `storage_path` the object behind it does not have yet.
    /// `kind` is the display word already, `"photos"` or `"traces"` — the
    /// same choice `bootstrapping`'s `table` makes, interpolated as-is rather
    /// than mapped through a second lookup. `done`/`total` count rows visited
    /// against this sweep's own fixed target — see `uploadPendingPhotos`.
    case uploadingBlobs(kind: String, done: Int, total: Int)
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

    /// How many Storage objects the last blob sweep failed to send. A failure
    /// there no longer stops the rows from going out — see
    /// `MirrorEngine.uploadPendingBlobs()` — so it has to be visible
    /// somewhere, or a durable Storage policy problem would look exactly like
    /// a clean run. Rewritten by every sweep, never accumulated.
    var failedUploads = 0

    /// Whether a bootstrap or a push is under way — `SyncProgress.isRunning`'s
    /// counterpart, needed for the same reason: a settings screen has to
    /// disable its own "amorcer" button while one is already running rather
    /// than let a second overlap the first.
    var isRunning: Bool {
        switch phase {
        case .idle, .failed: false
        case .uploadingBlobs, .bootstrapping, .pushing: true
        }
    }

    /// What to show, in words, never silent — the same rule `SyncProgress`
    /// follows and for the same reason: a mirror never configured and one
    /// that is merely idle must not read the same way, or "nothing to report"
    /// becomes indistinguishable from "nothing has ever happened".
    var statusText: String {
        let base: String = switch phase {
        case .idle:
            lastPushAt.map { "Dernière synchro \(Format.shortDate($0))" }
                ?? "Jamais synchronisé"
        case let .uploadingBlobs(kind, done, total):
            "Téléversement… \(kind) \(done)/\(total)"
        case let .bootstrapping(table, done, total):
            "Amorçage… \(table) \(done)/\(total)"
        case let .pushing(done, total):
            "Envoi… \(done)/\(total)"
        case let .failed(message):
            "Échec : \(message)"
        }
        // Appended rather than given a line of its own: the plan concedes the
        // mirror exactly one indicator, and a tally nobody reads is the same
        // as no tally at all.
        guard failedUploads > 0 else { return base }
        let plural = failedUploads > 1 ? "s" : ""
        return "\(base) — \(failedUploads) fichier\(plural) non envoyé\(plural)"
    }
}
