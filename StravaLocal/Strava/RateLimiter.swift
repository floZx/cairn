import Foundation

/// Strava reports quota on every response: `X-RateLimit-Limit: 200,2000` and
/// `X-RateLimit-Usage: <15min>,<daily>`.
struct RateLimitSnapshot: Sendable, Equatable {
    let shortTermUsage: Int
    let shortTermLimit: Int
    let dailyUsage: Int
    let dailyLimit: Int

    init(
        shortTermUsage: Int, shortTermLimit: Int, dailyUsage: Int, dailyLimit: Int
    ) {
        self.shortTermUsage = shortTermUsage
        self.shortTermLimit = shortTermLimit
        self.dailyUsage = dailyUsage
        self.dailyLimit = dailyLimit
    }

    init?(headers: [String: String]) {
        func value(_ name: String) -> [Int]? {
            let match = headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }
            guard let raw = match?.value else { return nil }
            let parts = raw.split(separator: ",").map {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            guard parts.count == 2, let first = parts[0], let second = parts[1] else {
                return nil
            }
            return [first, second]
        }
        guard let limits = value("X-RateLimit-Limit"),
              let usage = value("X-RateLimit-Usage")
        else { return nil }
        self.init(
            shortTermUsage: usage[0], shortTermLimit: limits[0],
            dailyUsage: usage[1], dailyLimit: limits[1]
        )
    }
}

/// Decides how long to wait before the next Strava request.
///
/// Pausing until the next window is the whole point: sync phase B walks
/// thousands of activities, and getting throttled mid-walk is both slower and
/// harder to reason about than waiting deliberately.
actor RateLimiter {
    private let clock: @Sendable () -> Date
    /// Requests deliberately left unused in each window, so an interactive
    /// action never gets blocked by a background sync burning the last call.
    private let reserve: Int
    private var latest: RateLimitSnapshot?
    private var consecutiveThrottles = 0

    private static let shortWindow: TimeInterval = 15 * 60
    private static let dailyWindow: TimeInterval = 24 * 60 * 60

    init(clock: @escaping @Sendable () -> Date = { Date() }, reserve: Int = 5) {
        self.clock = clock
        self.reserve = reserve
    }

    var snapshot: RateLimitSnapshot? { latest }

    /// Records a successful response's quota headers.
    ///
    /// Call this **only** for a non-throttled (2xx) response. Success is proof
    /// the throttling is over, so it clears any accumulated backoff — which is
    /// why it must never be called for a 429, even though Strava sends quota
    /// headers on those too. Use `observeTooManyRequests()` there instead.
    func observeSuccess(headers: [String: String]) {
        consecutiveThrottles = 0
        if let parsed = RateLimitSnapshot(headers: headers) {
            latest = parsed
        }
    }

    func observeTooManyRequests() {
        consecutiveThrottles += 1
    }

    func reset() {
        latest = nil
        consecutiveThrottles = 0
    }

    func delayBeforeNextRequest() -> TimeInterval {
        if consecutiveThrottles > 0 {
            // 30 s, 60 s, 120 s… capped at the 15-minute window.
            let backoff = 30 * pow(2, Double(consecutiveThrottles - 1))
            return min(backoff, Self.shortWindow)
        }
        guard let latest else { return 0 }

        let now = clock()
        if latest.dailyUsage >= latest.dailyLimit - reserve {
            return secondsUntilNextBoundary(of: Self.dailyWindow, from: now)
        }
        if latest.shortTermUsage >= latest.shortTermLimit - reserve {
            return secondsUntilNextBoundary(of: Self.shortWindow, from: now)
        }
        return 0
    }

    /// Strava's windows are aligned on UTC clock boundaries, not on first use.
    private func secondsUntilNextBoundary(
        of window: TimeInterval, from now: Date
    ) -> TimeInterval {
        let elapsed = now.timeIntervalSince1970.truncatingRemainder(dividingBy: window)
        return window - elapsed
    }
}
