import Foundation

/// How regularly one trains: a year of days, the weeks in a row that had an
/// outing, and where the year is heading at the current pace.
///
/// Counted in time and load rather than distance, for the reason the whole
/// statistics screen gives: a kilometre on a bike and one on foot are not the
/// same kilometre. The projection names a distance only for the sport one
/// spends the most time on, where it means something.
struct Regularity: Equatable {
    /// One cell per day, Monday-first weeks, oldest first, ending today.
    let days: [Day]
    /// Days with at least one outing, over the statistics' own period.
    let activeDays: Int
    /// Days the period covers, up to today.
    let periodDays: Int
    /// Consecutive weeks with an outing, ending on the current one — or on the
    /// last one, while the current week has none yet: a Monday morning is not
    /// a broken streak.
    let currentStreak: Int
    let bestStreak: Int
    /// Hours per week over the period.
    let weeklyHours: Double
    let projection: Projection?

    struct Day: Identifiable, Equatable {
        let date: Date
        /// 0 for Monday, 6 for Sunday.
        let weekday: Int
        /// 0 for the oldest week shown.
        let week: Int
        let load: Double
        let movingTime: Int

        var id: Date { date }
    }

    /// The year so far, carried to 31 December at the pace it has been
    /// going.
    struct Projection: Equatable {
        let year: Int
        let movingTimeSoFar: Int
        let projectedMovingTime: Int
        let mainSport: SportType?
        let mainSportDistanceSoFar: Double
        let projectedMainSportDistance: Double
    }

    /// Weeks the calendar shows, the current one included.
    static let weeksShown = 53

    static func compute(
        _ activities: [Activity],
        daily: TrainingLoad.Daily,
        periodStart: Date,
        now: Date = Date()
    ) -> Regularity {
        let calendar = ActivityStatistics.calendar
        guard let today = TrainingLoad.noon(of: now, calendar: calendar),
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let firstWeek = calendar.date(
                  byAdding: .weekOfYear, value: -(weeksShown - 1), to: thisWeek
              )
        else { return .empty }

        // The grid.
        var days: [Day] = []
        for week in 0..<weeksShown {
            for weekday in 0..<7 {
                guard let start = calendar.date(
                    byAdding: .day, value: week * 7 + weekday, to: firstWeek
                ), let date = TrainingLoad.noon(of: start, calendar: calendar),
                      date <= today
                else { continue }
                days.append(Day(
                    date: date, weekday: weekday, week: week,
                    load: daily.load[date] ?? 0,
                    movingTime: daily.movingTime[date] ?? 0
                ))
            }
        }

        // The period.
        let start = TrainingLoad.noon(of: periodStart, calendar: calendar) ?? periodStart
        let periodDays = max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
        let inPeriod = daily.movingTime.filter { $0.key >= start && $0.key <= today }
        let periodSeconds = inPeriod.values.reduce(0, +)

        // Streaks, over the whole history.
        let activeWeeks = Set(daily.load.keys.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0)?.start
        })
        var best = 0, run = 0
        if let earliest = activeWeeks.min() {
            var week = earliest
            while week <= thisWeek {
                run = activeWeeks.contains(week) ? run + 1 : 0
                best = max(best, run)
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
                week = next
            }
        }
        var current = 0
        var cursor = activeWeeks.contains(thisWeek)
            ? thisWeek
            : calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)
        while let week = cursor, activeWeeks.contains(week) {
            current += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: week)
        }

        return Regularity(
            days: days,
            activeDays: inPeriod.filter { $0.value > 0 }.count,
            periodDays: periodDays,
            currentStreak: current,
            bestStreak: best,
            weeklyHours: Double(periodSeconds) / 3600 / (Double(periodDays) / 7),
            projection: projection(activities, now: now)
        )
    }

    static let empty = Regularity(
        days: [], activeDays: 0, periodDays: 1,
        currentStreak: 0, bestStreak: 0, weeklyHours: 0, projection: nil
    )

    private static func projection(_ activities: [Activity], now: Date) -> Projection? {
        let calendar = ActivityStatistics.calendar
        let year = calendar.component(.year, from: now)
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let nextYear = calendar.date(byAdding: .year, value: 1, to: yearStart)
        else { return nil }
        let thisYear = activities.filter {
            guard let day = ActivityStatistics.day(of: $0) else { return false }
            return day >= yearStart && day < nextYear
        }
        guard !thisYear.isEmpty else { return nil }

        // Elapsed share of the year, today counted whole: on the evening of
        // 1 January one day of the year's 365 is done, not none.
        let elapsed = Double((calendar.dateComponents([.day], from: yearStart, to: now).day ?? 0) + 1)
        let length = Double(calendar.dateComponents([.day], from: yearStart, to: nextYear).day ?? 365)
        let factor = length / max(elapsed, 1)

        let seconds = thisYear.reduce(0) { $0 + $1.movingTime }
        let bySport = Dictionary(grouping: thisYear, by: \.sportType)
            .filter { $0.value.contains { $0.distance > 0 } }
        let main = bySport.max {
            $0.value.reduce(0) { $0 + $1.movingTime } < $1.value.reduce(0) { $0 + $1.movingTime }
        }
        let mainDistance = main?.value.reduce(0) { $0 + $1.distance } ?? 0

        return Projection(
            year: year,
            movingTimeSoFar: seconds,
            projectedMovingTime: Int(Double(seconds) * factor),
            mainSport: main?.key,
            mainSportDistanceSoFar: mainDistance,
            projectedMainSportDistance: mainDistance * factor
        )
    }
}
