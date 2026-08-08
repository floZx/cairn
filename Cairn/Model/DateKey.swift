import Foundation

/// A calendar day identity — "2026-08-08" — the unit the food journal is
/// keyed on. A validated string rather than a `Date`: a meal belongs to a
/// local calendar day, and normalising instants across DST switches is
/// exactly the bug class this avoids. suivinut stored TEXT dates for the
/// same reason, which also makes the import a straight copy.
struct DateKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    let raw: String

    init?(raw: String) {
        guard Self.components(of: raw) != nil else { return nil }
        self.raw = raw
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        raw = String(
            format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!
        )
    }

    /// Local midnight, for calendars and charts that need a real `Date`.
    func date(calendar: Calendar = .current) -> Date {
        let (year, month, day) = Self.components(of: raw)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    func advanced(by days: Int, calendar: Calendar = .current) -> DateKey {
        let moved = calendar.date(
            byAdding: .day, value: days, to: date(calendar: calendar)
        )!
        return DateKey(moved, calendar: calendar)
    }

    /// ISO ordering: lexicographic on the raw string *is* chronological,
    /// which is why the format is validated so strictly at init.
    static func < (lhs: DateKey, rhs: DateKey) -> Bool { lhs.raw < rhs.raw }

    var description: String { raw }

    private static func components(of raw: String) -> (Int, Int, Int)? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }
}
