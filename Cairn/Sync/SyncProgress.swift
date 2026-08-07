import Foundation
import Observation

enum SyncPhase: Sendable, Equatable {
    case idle
    case summaries(page: Int)
    case streams(done: Int, total: Int)
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

    var isRunning: Bool {
        switch phase {
        case .idle, .failed: false
        case .summaries, .streams, .waitingForQuota: true
        }
    }

    var statusText: String {
        switch phase {
        case .idle:
            lastRunAt.map {
                "Dernière synchro \(Format.shortDate($0))"
            } ?? "Jamais synchronisé"
        case let .summaries(page):
            "Import des activités… (page \(page))"
        case let .streams(done, total):
            "Import des traces… \(done)/\(total)"
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
        case .waitingForQuota:
            "Quota atteint"
        case .failed:
            "Échec"
        }
    }

    var fractionCompleted: Double? {
        guard case let .streams(done, total) = phase, total > 0 else { return nil }
        return Double(done) / Double(total)
    }
}
