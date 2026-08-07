import Foundation
import Observation

enum SyncPhase: Sendable, Equatable {
    case idle
    case summaries(page: Int)
    case streams(done: Int, total: Int)
    case completing(done: Int, total: Int)
    case waitingForQuota(until: Date)
    case failed(String)
}

/// UI-facing sync state. Lives on the main actor so views can observe it
/// directly; the engine pushes updates into it.
@MainActor
@Observable
final class SyncProgress {
    var phase: SyncPhase = .idle
    var lastRunAt: Date?
    var quota: RateLimitSnapshot?
    /// Activities whose charts are still to be downloaded.
    ///
    /// Surfaced because nothing else could answer "is it finished?". Phase B
    /// works from a persisted queue that survives quits, so an idle app with a
    /// backlog and an idle app with nothing left to do looked identical.
    var pendingStreams: Int = 0
    /// Activities still missing their detail or their photos, from before Cairn
    /// fetched either. Drains a little at each launch and fully on ⌘R.
    var pendingBackfill: Int = 0

    /// What is left to fetch, in words, or that nothing is.
    ///
    /// Never silent: an app with a backlog and an app with nothing left to do
    /// read identically when the phrase is simply omitted, which is the whole
    /// reason this exists.
    static func remainingText(streams: Int, backfill: Int) -> String {
        var parts: [String] = []
        if streams > 0 {
            let noun = streams > 1 ? "activités" : "activité"
            parts.append("\(streams) \(noun) en attente de leurs courbes")
        }
        if backfill > 0 {
            parts.append("\(backfill) à compléter (détail et photos)")
        }
        return parts.isEmpty ? "tout est à jour" : parts.joined(separator: ", ")
    }

    var isRunning: Bool {
        switch phase {
        case .idle, .failed: false
        case .summaries, .streams, .completing, .waitingForQuota: true
        }
    }

    var statusText: String {
        switch phase {
        case .idle:
            [
                lastRunAt.map { "Dernière synchro \(Format.shortDate($0))" }
                    ?? "Jamais synchronisé",
                Self.remainingText(
                    streams: pendingStreams, backfill: pendingBackfill
                ),
            ].joined(separator: " · ")
        case let .summaries(page):
            "Import des activités… (page \(page))"
        case let .streams(done, total):
            "Import des traces… \(done)/\(total)"
        case let .completing(done, total):
            "Récupération des nouvelles activités… \(done)/\(total)"
        case let .waitingForQuota(until):
            "Quota Strava atteint, reprise à \(Format.time(until))"
        case let .failed(message):
            "Échec : \(message)"
        }
    }

    /// Short form for the toolbar, where the detailed wording would be truncated
    /// and would change width on every page. Digits are rendered monospaced by
    /// the caller so a counter ticking over doesn't reflow the toolbar.
    var toolbarText: String {
        switch phase {
        case .idle:
            ""
        case let .summaries(page):
            "Activités \(page)"
        case let .streams(done, total):
            "Traces \(done)/\(total)"
        case let .completing(done, total):
            "Nouvelles \(done)/\(total)"
        case .waitingForQuota:
            "Quota atteint"
        case .failed:
            "Échec"
        }
    }

    var fractionCompleted: Double? {
        switch phase {
        case let .streams(done, total) where total > 0,
             let .completing(done, total) where total > 0:
            Double(done) / Double(total)
        default:
            nil
        }
    }
}
