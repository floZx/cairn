import Foundation

/// Whether a chart slot is a week or a month.
///
/// Follows the period rather than being a control of its own: a short window
/// charted monthly is three bars and no shape at all, while a year charted weekly
/// is a fifty-two-bar comb with an axis nothing can label. Neither is a choice
/// worth offering.
enum StatsGranularity: Sendable {
    case week
    case month

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// What the chart's own heading calls it.
    var sectionTitle: String {
        switch self {
        case .week: "Par semaine"
        case .month: "Par mois"
        }
    }
}

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

    /// Weeks on the short windows, months on the long ones.
    ///
    /// Training is planned in weeks, and thirteen bars carry a shape that three
    /// cannot. Past six months the count makes weekly bars unreadable, and
    /// smoothing to months is exactly what comparing two years wants anyway.
    var granularity: StatsGranularity {
        switch self {
        case .threeMonths, .sixMonths: .week
        case .twelveMonths, .currentYear: .month
        }
    }

    /// How many slots the window covers, ending on the current one. Counted in
    /// whichever unit `granularity` uses.
    func slotCount(now: Date, calendar: Calendar) -> Int {
        switch self {
        case .threeMonths: 13
        case .sixMonths: 26
        case .twelveMonths: 12
        // January through the current month, so the window grows over the year.
        case .currentYear: calendar.component(.month, from: now)
        }
    }

    /// How far back the comparison window sits, in the granularity's own unit.
    ///
    /// A calendar year compares against the same months a year earlier, so the
    /// two cover the same season. Every other window compares against the span
    /// immediately before it, which is what "the previous 3 months" means.
    func comparisonShift(now: Date, calendar: Calendar) -> Int {
        switch self {
        case .currentYear: 12
        case .threeMonths, .sixMonths, .twelveMonths:
            slotCount(now: now, calendar: calendar)
        }
    }

    static let storageKey = "statsPeriod"
}
