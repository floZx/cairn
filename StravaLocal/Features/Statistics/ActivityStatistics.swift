import Foundation

/// Aggregates over a set of activities — whichever set the filters have left.
///
/// Pure computation over values already in memory: no fetch, no pre-aggregation.
/// A few hundred activities is nothing to sum, and keeping it a plain function of
/// its input is what makes it testable.
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
    /// Twelve contiguous months ending on the most recent activity's month.
    let months: [MonthTotals]

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

    struct MonthTotals: Identifiable, Equatable {
        let month: Date
        let distance: Double
        let elevationGain: Double

        var id: Date { month }
    }

    private static let calendar = Calendar(identifier: .gregorian)

    static func compute(for activities: [Activity]) -> ActivityStatistics {
        guard !activities.isEmpty else { return .empty }

        return ActivityStatistics(
            count: activities.count,
            movingTime: activities.reduce(0) { $0 + $1.movingTime },
            elevationGain: activities.reduce(0) { $0 + $1.totalElevationGain },
            sports: sportTotals(for: activities),
            records: records(for: activities),
            months: monthlyTotals(for: activities)
        )
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

    /// Twelve contiguous months ending on the most recent activity's month.
    ///
    /// Contiguous, and that is the point: listing only the months that have
    /// activities would put January next to December and read as a steady year.
    /// Empty months are worth showing as zero.
    private static func monthlyTotals(for activities: [Activity]) -> [MonthTotals] {
        let months = activities.compactMap { startOfMonth(of: $0.startLocalDate) }
        guard let mostRecent = months.max() else { return [] }

        var totals: [Date: (distance: Double, elevation: Double)] = [:]
        for activity in activities {
            guard let month = startOfMonth(of: activity.startLocalDate) else {
                continue
            }
            totals[month, default: (0, 0)].distance += activity.distance
            totals[month, default: (0, 0)].elevation += activity.totalElevationGain
        }

        return (0..<12).reversed().compactMap { monthsBack in
            guard let month = calendar.date(
                byAdding: .month, value: -monthsBack, to: mostRecent
            ) else { return nil }
            let total = totals[month] ?? (distance: 0, elevation: 0)
            return MonthTotals(
                month: month, distance: total.distance, elevationGain: total.elevation
            )
        }
    }

    private static func startOfMonth(of date: Date) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }
}
