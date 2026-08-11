import Foundation
import SwiftData

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
    /// One entry per slot of the period — a week or a month, per its granularity
    /// — each carrying its counterpart from the preceding period.
    let slots: [SlotTotals]

    /// Nothing at all, for a window that could not be built. Not the same as an
    /// empty period, which still lays its months out as zeros.
    static let empty = ActivityStatistics(
        count: 0, movingTime: 0, elevationGain: 0,
        sports: [], records: [], slots: []
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
        /// The activity holding the record, so a click can open it. Carried
        /// rather than looked up again from the name and date: two outings can
        /// share both, and opening the wrong one would be worse than not
        /// opening anything.
        let activityID: PersistentIdentifier
        let activityName: String
        let sport: SportType
        /// The instant, with the clock it is read on beside it — the outing's
        /// own, so a record set abroad shows the date it was set there.
        let date: Date
        let timeZone: TimeZone

        var id: String { kind.rawValue }
        var formattedDate: String { Format.dateOnly(date, in: timeZone) }
        var formattedValue: String { kind.formatted(value) }
    }

    /// One slot of the period, beside its counterpart in the one before.
    struct SlotTotals: Identifiable, Equatable {
        /// The first day of the week or month this covers.
        let start: Date
        let distance: Double
        let elevationGain: Double
        /// The slot this is compared against — a period or a year earlier.
        let comparisonStart: Date
        let comparisonDistance: Double
        let comparisonElevationGain: Double

        var id: Date { start }
    }

    /// Monday-first, per French usage: a training week that began on Sunday would
    /// split every weekend across two bars.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    static func compute(
        for activities: [Activity],
        period: StatsPeriod,
        now: Date = Date()
    ) -> ActivityStatistics {
        let unit = period.granularity.component
        let count = period.slotCount(now: now, calendar: calendar)
        let shift = period.comparisonShift(now: now, calendar: calendar)
        // A calendar year is measured in months whatever its granularity, so the
        // comparison shifts by months even when the slots are months too.
        let shiftUnit: Calendar.Component =
            period == .currentYear ? .month : unit
        guard count > 0, let currentSlot = startOfSlot(of: now, unit: unit) else {
            return .empty
        }

        // Chronological, ending on the current slot.
        let slots: [Date] = (0..<count).reversed().compactMap {
            calendar.date(byAdding: unit, value: -$0, to: currentSlot)
        }
        guard let firstSlot = slots.first else { return .empty }

        let bySlot = totals(for: activities, unit: unit)
        let inPeriod = activities.filter { activity in
            guard let day = day(of: activity),
                  let slot = startOfSlot(of: day, unit: unit)
            else { return false }
            return slot >= firstSlot && slot <= currentSlot
        }

        return ActivityStatistics(
            count: inPeriod.count,
            movingTime: inPeriod.reduce(0) { $0 + $1.movingTime },
            elevationGain: inPeriod.reduce(0) { $0 + $1.totalElevationGain },
            sports: sportTotals(for: inPeriod),
            records: records(for: inPeriod),
            slots: slots.compactMap { slot in
                guard let comparisonStart = calendar.date(
                    byAdding: shiftUnit, value: -shift, to: slot
                ) else { return nil }
                let current = bySlot[slot] ?? .zero
                // Aligned on the comparison slot's own start, so a shift that
                // lands mid-week still reads the right bucket.
                let previousKey = startOfSlot(of: comparisonStart, unit: unit)
                let previous = previousKey.flatMap { bySlot[$0] } ?? .zero
                return SlotTotals(
                    start: slot,
                    distance: current.distance,
                    elevationGain: current.elevation,
                    comparisonStart: comparisonStart,
                    comparisonDistance: previous.distance,
                    comparisonElevationGain: previous.elevation
                )
            }
        )
    }

    private struct SlotSums {
        var distance: Double = 0
        var elevation: Double = 0

        static let zero = SlotSums()
    }

    /// Every slot at once, including those outside the period: the comparison
    /// series reads slots the period itself does not cover.
    private static func totals(
        for activities: [Activity], unit: Calendar.Component
    ) -> [Date: SlotSums] {
        var totals: [Date: SlotSums] = [:]
        for activity in activities {
            guard let day = day(of: activity),
                  let slot = startOfSlot(of: day, unit: unit)
            else { continue }
            totals[slot, default: .zero].distance += activity.distance
            totals[slot, default: .zero].elevation += activity.totalElevationGain
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
                activityID: best.id,
                activityName: best.name,
                sport: best.sportType,
                date: best.startDate,
                timeZone: best.timeZone
            )
        }
    }

    /// The first instant of the week or month a date falls in.
    private static func startOfSlot(
        of date: Date, unit: Calendar.Component
    ) -> Date? {
        calendar.dateInterval(of: unit, for: date)?.start
    }

    /// The calendar day an outing happened on, placed in the reader's calendar.
    ///
    /// Two clocks meet here and neither can be dropped. *Which day* an outing
    /// belongs to is a question for the clock it happened on — a run at 23:30
    /// belongs to that evening, wherever one reads it from later. *Which week
    /// or month* that day falls in is a question for the reader's calendar,
    /// because that is what the histogram's bars are.
    ///
    /// So the day is read in the activity's zone and rebuilt in ours, at noon:
    /// only the date matters, and midday is the hour furthest from both edges
    /// of a daylight-saving change.
    ///
    /// `startLocalDate` used to stand in for this, and could not: it holds the
    /// wall clock encoded as if it were UTC, so read in the reader's calendar
    /// it lands offset by that calendar's own shift — a 23:30 outing in UTC+2
    /// was filed on the following day, and at the end of a month or a week, in
    /// the following bar.
    static func day(of activity: Activity) -> Date? {
        var there = Calendar(identifier: .gregorian)
        there.timeZone = activity.timeZone
        let parts = there.dateComponents(
            [.year, .month, .day], from: activity.startDate
        )
        var here = DateComponents()
        here.year = parts.year
        here.month = parts.month
        here.day = parts.day
        here.hour = 12
        return calendar.date(from: here)
    }
}
