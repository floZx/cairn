import Foundation

/// Aggregates over a set of activities, for one period and the one before it.
///
/// Pure computation over values already in memory: no fetch, no pre-aggregation.
/// A few hundred activities is nothing to sum, and keeping it a plain function of
/// its inputs is what makes it testable — `now` included, so the window is never
/// a moving target under a test.
///
/// The shape of it answers one problem: **adding different sports together says
/// nothing**. A total distance mixing e-bike rides, runs and swims informs on
/// nothing at all. So the figures that add up honestly — count, time, climbing —
/// are the only global ones, and distance is reported per sport.
struct ActivityStatistics: Equatable {
    let count: Int
    let movingTime: Int
    let elevationGain: Double
    /// Per sport, so distances are never added across sports.
    let sports: [SportTotals]
    let records: [Record]
    /// One entry per month of the period, each carrying its counterpart from the
    /// preceding period.
    let months: [MonthTotals]

    /// Nothing at all, for a window that could not be built. Not the same as an
    /// empty period, which still lays its months out as zeros.
    static let empty = ActivityStatistics(
        count: 0, movingTime: 0, elevationGain: 0,
        sports: [], records: [], months: []
    )

    struct SportTotals: Identifiable, Equatable {
        let sport: SportType
        let count: Int
        let distance: Double
        let movingTime: Int
        let elevationGain: Double

        var id: SportType { sport }
    }

    /// What a record measures, and how to read it.
    enum RecordKind: String, CaseIterable, Identifiable, Sendable {
        case distance
        case elevation
        case duration

        var id: String { rawValue }

        var label: String {
            switch self {
            case .distance: "La plus longue"
            case .elevation: "La plus grimpante"
            case .duration: "La plus longue en temps"
            }
        }

        func formatted(_ value: Double) -> String {
            switch self {
            case .distance: Format.distance(value)
            case .elevation: Format.elevation(value)
            case .duration: Format.durationCompact(Int(value))
            }
        }

        /// The figure this kind ranks on. Raw units: metres, metres, seconds.
        func value(of activity: Activity) -> Double {
            switch self {
            case .distance: activity.distance
            case .elevation: activity.totalElevationGain
            case .duration: Double(activity.movingTime)
            }
        }
    }

    struct Record: Identifiable, Equatable {
        let kind: RecordKind
        let value: Double
        let activityName: String
        let sport: SportType
        let date: Date

        var id: String { kind.rawValue }
        var formattedValue: String { kind.formatted(value) }
    }

    /// One month of the period, beside the matching month of the one before.
    struct MonthTotals: Identifiable, Equatable {
        let month: Date
        let distance: Double
        let elevationGain: Double
        /// The month this is compared against — a period or a year earlier.
        let comparisonMonth: Date
        let comparisonDistance: Double
        let comparisonElevationGain: Double

        var id: Date { month }
    }

    private static let calendar = Calendar(identifier: .gregorian)

    static func compute(
        for activities: [Activity],
        period: StatsPeriod,
        now: Date = Date()
    ) -> ActivityStatistics {
        let count = period.monthCount(now: now, calendar: calendar)
        let shift = period.comparisonShift(now: now, calendar: calendar)
        guard count > 0, let currentMonth = startOfMonth(of: now) else {
            return .empty
        }

        // Chronological, ending on the current month.
        let months: [Date] = (0..<count).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: currentMonth)
        }
        guard let firstMonth = months.first else { return .empty }

        let byMonth = totalsByMonth(for: activities)
        let inPeriod = activities.filter { activity in
            guard let month = startOfMonth(of: activity.startLocalDate) else {
                return false
            }
            return month >= firstMonth && month <= currentMonth
        }

        return ActivityStatistics(
            count: inPeriod.count,
            movingTime: inPeriod.reduce(0) { $0 + $1.movingTime },
            elevationGain: inPeriod.reduce(0) { $0 + $1.totalElevationGain },
            sports: sportTotals(for: inPeriod),
            records: records(for: inPeriod),
            months: months.compactMap { month in
                guard let comparisonMonth = calendar.date(
                    byAdding: .month, value: -shift, to: month
                ) else { return nil }
                let current = byMonth[month] ?? .zero
                let previous = byMonth[comparisonMonth] ?? .zero
                return MonthTotals(
                    month: month,
                    distance: current.distance,
                    elevationGain: current.elevation,
                    comparisonMonth: comparisonMonth,
                    comparisonDistance: previous.distance,
                    comparisonElevationGain: previous.elevation
                )
            }
        )
    }

    private struct MonthSums {
        var distance: Double = 0
        var elevation: Double = 0

        static let zero = MonthSums()
    }

    /// Every month at once, including those outside the period: the comparison
    /// series reads months the period itself does not cover.
    private static func totalsByMonth(
        for activities: [Activity]
    ) -> [Date: MonthSums] {
        var totals: [Date: MonthSums] = [:]
        for activity in activities {
            guard let month = startOfMonth(of: activity.startLocalDate) else {
                continue
            }
            totals[month, default: .zero].distance += activity.distance
            totals[month, default: .zero].elevation += activity.totalElevationGain
        }
        return totals
    }

    private static func sportTotals(for activities: [Activity]) -> [SportTotals] {
        Dictionary(grouping: activities, by: \.sportType)
            .map { sport, group in
                SportTotals(
                    sport: sport,
                    count: group.count,
                    distance: group.reduce(0) { $0 + $1.distance },
                    movingTime: group.reduce(0) { $0 + $1.movingTime },
                    elevationGain: group.reduce(0) { $0 + $1.totalElevationGain }
                )
            }
            // By time rather than distance: it is the one measure that compares
            // across sports, so it puts the most-practised first whether or not
            // the sport covers ground. Sport name breaks ties, so the order is
            // stable rather than following the dictionary's.
            .sorted {
                $0.movingTime == $1.movingTime
                    ? $0.sport.displayName < $1.sport.displayName
                    : $0.movingTime > $1.movingTime
            }
    }

    private static func records(for activities: [Activity]) -> [Record] {
        RecordKind.allCases.compactMap { kind in
            guard let best = activities.max(by: {
                kind.value(of: $0) < kind.value(of: $1)
            }), kind.value(of: best) > 0 else { return nil }

            return Record(
                kind: kind,
                value: kind.value(of: best),
                activityName: best.name,
                sport: best.sportType,
                date: best.startLocalDate
            )
        }
    }

    private static func startOfMonth(of date: Date) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }
}
