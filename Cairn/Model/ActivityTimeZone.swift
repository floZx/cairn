import Foundation

/// Where an outing happened, as a time zone.
///
/// Strava sends `timezone` as `"(GMT+01:00) Europe/Paris"` — a printed offset
/// and an IANA identifier. **Only the identifier is usable.** The offset is the
/// zone's *standard* time and does not move with daylight saving: every Paris
/// activity carries `(GMT+01:00)`, in August as in January. Trusting it would
/// put every summer outing an hour early.
enum ActivityTimeZone {
    static func parse(_ raw: String?) -> TimeZone? {
        guard let raw else { return nil }
        // The identifier is what follows the offset, when there is one. Split
        // on the last space rather than the first: an identifier never contains
        // one, while the offset is always a single token before it.
        let identifier = raw.split(separator: " ").last.map(String.init) ?? raw
        return TimeZone(identifier: identifier)
    }
}

extension Activity {
    /// The zone this outing's clock was on, or this Mac's when it is unknown.
    ///
    /// Falling back to the current zone rather than to UTC: an activity with no
    /// zone recorded is one entered by hand or imported from a file, and both
    /// happened wherever the person doing it was.
    var timeZone: TimeZone {
        ActivityTimeZone.parse(timezoneIdentifier) ?? .current
    }
}
