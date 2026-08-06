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

    static func elevation(_ metres: Double) -> String {
        "\(Int(metres.rounded())) m"
    }

    /// Runners think in pace, cyclists in speed. Showing the wrong one makes
    /// every number in the row useless to read at a glance.
    static func speed(_ metresPerSecond: Double, sport: SportType) -> String {
        guard metresPerSecond > 0 else { return "—" }
        switch sport {
        case .run, .trailRun, .walk, .hike, .swim:
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

    static func heartrate(_ bpm: Double?) -> String {
        bpm.map { "\(Int($0.rounded())) bpm" } ?? "—"
    }

    static func power(_ watts: Double?) -> String {
        watts.map { "\(Int($0.rounded())) W" } ?? "—"
    }

    static func cadence(_ rpm: Double?) -> String {
        rpm.map { "\(Int($0.rounded())) rpm" } ?? "—"
    }
}
