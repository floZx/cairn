import Foundation

/// The window the statistics view measures, and what it compares against.
///
/// Owned by that view rather than taken from the sidebar's date filter, and that
/// is not a duplicate: comparing against the preceding period means reading
/// activities the sidebar filter would have already removed. Every other
/// criterion — sport, labels, distance, region — still comes from the sidebar.
enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case threeMonths
    case sixMonths
    case twelveMonths
    case currentYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .threeMonths: "3 mois"
        case .sixMonths: "6 mois"
        case .twelveMonths: "12 mois"
        case .currentYear: "Année en cours"
        }
    }

    /// How the comparison series is named on the chart.
    var comparisonName: String {
        switch self {
        case .currentYear: "Année précédente"
        default: "Période précédente"
        }
    }

    /// How many months the window covers, ending on the current one.
    func monthCount(now: Date, calendar: Calendar) -> Int {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .twelveMonths: 12
        // January through the current month, so the window grows over the year.
        case .currentYear: calendar.component(.month, from: now)
        }
    }

    /// How far back the comparison window sits, in months.
    ///
    /// A calendar year compares against the same months a year earlier, so the
    /// two cover the same season. A rolling window compares against the span
    /// immediately before it, which is what "the previous 3 months" means.
    func comparisonShift(now: Date, calendar: Calendar) -> Int {
        switch self {
        case .currentYear: 12
        case .threeMonths, .sixMonths, .twelveMonths:
            monthCount(now: now, calendar: calendar)
        }
    }

    static let storageKey = "statsPeriod"
}
