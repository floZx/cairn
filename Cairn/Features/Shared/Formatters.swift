import Foundation

/// Display formatting, centralised so the same distance never appears two ways.
enum Format {
    private static let oneDecimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func distance(_ metres: Double) -> String {
        guard metres >= 1000 else { return "\(Int(metres.rounded())) m" }
        let kilometres = oneDecimal.string(from: (metres / 1000) as NSNumber) ?? "0,0"
        return "\(kilometres) km"
    }

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min \(seconds % 60) s" }
        return String(format: "%d h %02d", seconds / 3600, (seconds % 3600) / 60)
    }

    /// Minutes at the finest, for scanning a column of durations.
    ///
    /// Seconds are noise when comparing outings at a glance — they matter on a
    /// lap, which is why `duration` keeps them. Rounded rather than truncated so
    /// 1 h 29 min 45 s reads as 1 h 30 like everywhere else.
    static func durationCompact(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    static func elevation(_ metres: Double) -> String {
        "\(Int(metres.rounded())) m"
    }

    /// A number the user typed, written back the way they would write it.
    ///
    /// No trailing ",0" on a round figure, and a comma rather than a point on
    /// the rest — the filter fields are French-facing.
    static func typedNumber(_ value: Double) -> String {
        guard value != value.rounded() else { return "\(Int(value))" }
        return oneDecimal.string(from: value as NSNumber) ?? "\(value)"
    }

    /// Runners think in pace, cyclists in speed. Showing the wrong one makes
    /// every number in the row useless to read at a glance.
    static func speed(_ metresPerSecond: Double, sport: SportType) -> String {
        guard metresPerSecond > 0 else { return "—" }
        switch sport {
        case .swim:
            // Swimmers read pace per 100 m, never per kilometre.
            let secondsPerHundred = Int((100 / metresPerSecond).rounded())
            return String(
                format: "%d:%02d/100 m", secondsPerHundred / 60, secondsPerHundred % 60
            )
        case .run, .trailRun, .walk, .hike:
            let secondsPerKilometre = Int((1000 / metresPerSecond).rounded())
            return String(
                format: "%d:%02d/km", secondsPerKilometre / 60, secondsPerKilometre % 60
            )
        default:
            let kilometresPerHour = metresPerSecond * 3.6
            let value = oneDecimal.string(from: kilometresPerHour as NSNumber) ?? "0,0"
            return "\(value) km/h"
        }
    }

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// All digits, fixed width: for a table column, where "9 août 2026" and
    /// "31 juil. 2026" are two different widths and neither lines up with the
    /// next. `dateFormat` rather than a style, because a style is the system's
    /// choice and this one has to be the same length on every row.
    private static let numericDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// All three pinned to French rather than the host locale: the whole
    /// interface is in French, and a date rendered in the system language would
    /// be the one English string on the screen.
    static func longDate(_ date: Date) -> String {
        longDateFormatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    /// Weekday and full date, no time — the food journal is keyed on
    /// calendar days, an hour would be an invention.
    static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    /// Date without a time, for the list — the hour of the day adds noise to a
    /// column that is mostly used for sorting and scanning.
    static func dateOnly(_ date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    static func numericDate(_ date: Date) -> String {
        numericDateFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Absent on activities recorded without a monitor — and Strava sends zero
    /// for some manual entries, which means the same thing.
    static func heartrate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "—" }
        return "\(Int(bpm.rounded())) bpm"
    }

    static func power(_ watts: Double?) -> String {
        watts.map { "\(Int($0.rounded())) W" } ?? "—"
    }

    /// Metres of climbing per kilometre. A dash when there is no distance to
    /// divide by, rather than a meaningless zero.
    static func elevationPerKilometre(_ metresPerKilometre: Double) -> String {
        guard metresPerKilometre > 0 else { return "—" }
        return "\(Int(metresPerKilometre.rounded())) m/km"
    }

    static func cadence(_ rpm: Double?) -> String {
        rpm.map { "\(Int($0.rounded())) rpm" } ?? "—"
    }

    private static let signedTwoDecimalsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        // U+2212, the real minus — a hyphen reads as a dash in running text.
        formatter.negativePrefix = "−"
        return formatter
    }()

    /// Signed rates and deltas: two decimals so −0,04 kg/sem never rounds
    /// to the lie « −0,0 ».
    static func signedTwoDecimals(_ value: Double) -> String {
        signedTwoDecimalsFormatter.string(from: value as NSNumber) ?? "\(value)"
    }
}
