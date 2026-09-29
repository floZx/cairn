import Foundation
import os

/// One logger per subsystem, readable in Console or with
/// `/usr/bin/log show --predicate 'subsystem == "com.florianmaisonnial.Cairn"' --info`.
///
/// Before these, a failed save in the plan, a Garmin call refused or the
/// launch maintenance giving up all vanished inside a `try?` — found, when
/// they were found at all, by guessing.
enum Log {
    private static let subsystem = "com.florianmaisonnial.Cairn"

    static let maintenance = Logger(subsystem: subsystem, category: "maintenance")
    static let journal = Logger(subsystem: subsystem, category: "journal")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let garmin = Logger(subsystem: subsystem, category: "garmin")
}

extension Logger {
    /// `try?` that leaves a line when it fails. A cancellation is not a
    /// failure: it is noted at debug level only.
    @discardableResult
    func attempt<T>(_ what: String, _ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            record(error, what)
            return nil
        }
    }

    /// Runs on the caller's actor, so the body may touch what that actor owns.
    @discardableResult
    func attempt<T>(
        _ what: String,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async -> T? {
        do {
            return try await body()
        } catch {
            record(error, what)
            return nil
        }
    }

    private func record(_ error: any Error, _ what: String) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            debug("\(what, privacy: .public) : interrompu")
        } else {
            self.error("\(what, privacy: .public) : \(String(describing: error), privacy: .public)")
        }
    }
}
