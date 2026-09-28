import Foundation
import SwiftData

/// How one sport is going: each outing's speed and heart rate over the
/// period, the trend through them, the sport's all-time records and the gear
/// it wears out.
///
/// One sport at a time, always: a trend through runs and rides together would
/// be a trend through the mix, not through either.
struct SportProgress: Equatable {
    let sport: SportType
    let points: [Point]
    let records: [ActivityStatistics.Record]
    let gear: [GearUse]

    /// What the progression chart can plot.
    enum Measure: String, CaseIterable, Identifiable {
        case speed, heartrate, efficiency

        var id: String { rawValue }

        func label(for sport: SportType) -> String {
            switch self {
            case .speed: Format.readsAsPace(sport) ? "Allure" : "Vitesse"
            case .heartrate: "FC moyenne"
            case .efficiency: "Efficacité"
            }
        }

        /// Whether a higher value is better — so the chart can put "better"
        /// at the top whatever the unit, and the trend can be coloured by it.
        var higherIsBetter: Bool {
            switch self {
            case .speed, .efficiency: true
            case .heartrate: false
            }
        }
    }

    struct Point: Identifiable, Equatable {
        let activityID: PersistentIdentifier
        let name: String
        let day: Date
        /// Metres per second — in effort-kilometres where the sport counts
        /// them, see `usesEffortDistance`.
        let speed: Double
        let heartrate: Double?

        var id: PersistentIdentifier { activityID }

        /// Metres covered per heartbeat: speed at a given effort. The one that
        /// says fitness improved, where speed alone may only say one ran
        /// harder.
        var efficiency: Double? {
            guard let heartrate, heartrate > 0 else { return nil }
            return speed * 60 / heartrate
        }

        func value(_ measure: Measure) -> Double? {
            switch measure {
            case .speed: speed
            case .heartrate: heartrate
            case .efficiency: efficiency
            }
        }
    }

    struct GearUse: Identifiable, Equatable {
        let name: String
        /// Everything it has done, summed over Cairn's own outings. Not
        /// Strava's `distance` for the gear, which drifts from them: one pair
        /// of shoes read 1 043 km there against 1 405 km of outings here.
        let totalDistance: Double
        /// Outings of this sport with it, over the period.
        let count: Int
        var id: String { name }
    }

    /// Trail and hiking speeds mean little without the climbing: ten
    /// kilometres at 600 m D+ is not a slow ten kilometres. The usual answer
    /// is the effort-kilometre — each 100 m of climbing counts as one more
    /// kilometre — and it is used for their speed and efficiency here.
    static func usesEffortDistance(_ sport: SportType) -> Bool {
        sport == .trailRun || sport == .hike
    }

    static func effortDistance(of activity: Activity) -> Double {
        usesEffortDistance(activity.sportType)
            ? activity.distance + activity.totalElevationGain * 10
            : activity.distance
    }

    /// Sports worth a progression: those that cover ground, with at least
    /// three outings over the period, the most practised first.
    static func sports(in activities: [Activity], since start: Date) -> [SportType] {
        let inPeriod = activities.filter {
            $0.distance > 0 && (ActivityStatistics.day(of: $0).map { $0 >= start } ?? false)
        }
        return Dictionary(grouping: inPeriod, by: \.sportType)
            .filter { $0.value.count >= 3 }
            .sorted {
                $0.value.reduce(0) { $0 + $1.movingTime } > $1.value.reduce(0) { $0 + $1.movingTime }
            }
            .map(\.key)
    }

    /// Kilometres per gear id over every outing in the store, whatever the
    /// sidebar filters: a pair of shoes wears on all its runs, not only on
    /// those the filters keep.
    static func gearDistances(in context: ModelContext) -> [String: Double] {
        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.gearID != nil })
        let activities = (try? context.fetch(descriptor)) ?? []
        return activities.reduce(into: [:]) { totals, activity in
            if let id = activity.gearID { totals[id, default: 0] += activity.distance }
        }
    }

    static func compute(
        _ activities: [Activity],
        sport: SportType,
        since start: Date,
        gearDistances: [String: Double] = [:]
    ) -> SportProgress {
        let ofSport = activities.filter { $0.sportType == sport }
        let inPeriod = ofSport.filter {
            ActivityStatistics.day(of: $0).map { $0 >= start } ?? false
        }
        // Short outings and walks to the car say nothing about form.
        let points = inPeriod
            .filter { $0.movingTime >= 600 && $0.distance >= 1000 }
            .compactMap { activity -> Point? in
                guard let day = ActivityStatistics.day(of: activity) else { return nil }
                return Point(
                    activityID: activity.id,
                    name: activity.name,
                    day: day,
                    speed: effortDistance(of: activity) / Double(activity.movingTime),
                    heartrate: activity.averageHeartrate
                )
            }
            .sorted { $0.day < $1.day }

        let gear = Dictionary(grouping: inPeriod.filter { $0.gearID != nil }) { $0.gearID! }
            .compactMap { id, group -> GearUse? in
                guard let item = group.first?.gear else { return nil }
                return GearUse(
                    name: item.name,
                    totalDistance: gearDistances[id] ?? 0,
                    count: group.count
                )
            }
            .sorted { $0.count > $1.count }

        return SportProgress(
            sport: sport,
            points: points,
            records: records(of: ofSport),
            gear: gear
        )
    }

    /// All-time records of the sport: the longest, the one that climbed most,
    /// and the fastest — among outings at least half the sport's median
    /// distance, or a two-kilometre jog would hold it for ever.
    private static func records(of activities: [Activity]) -> [ActivityStatistics.Record] {
        func record(_ kind: ActivityStatistics.RecordKind, _ best: Activity?, _ value: Double?) -> ActivityStatistics.Record? {
            guard let best, let value, value > 0 else { return nil }
            return ActivityStatistics.Record(
                kind: kind, value: value, activityID: best.id,
                activityName: best.name, sport: best.sportType,
                date: best.startDate, timeZone: best.timeZone
            )
        }
        let longest = activities.max { $0.distance < $1.distance }
        let climbing = activities.max { $0.totalElevationGain < $1.totalElevationGain }
        // In effort-kilometres where the sport counts them, like the chart:
        // otherwise the fastest trail is simply the flattest one.
        func effortSpeed(_ activity: Activity) -> Double {
            effortDistance(of: activity) / Double(activity.movingTime)
        }
        let distances = activities.map(effortDistance(of:)).filter { $0 > 0 }.sorted()
        let median = distances.isEmpty ? 0 : distances[distances.count / 2]
        let fastest = activities
            .filter { effortDistance(of: $0) >= median / 2 && $0.movingTime > 0 }
            .max { effortSpeed($0) < effortSpeed($1) }
        return [
            record(.distance, longest, longest?.distance),
            record(.elevation, climbing, climbing?.totalElevationGain),
            record(.speed, fastest, fastest.map(effortSpeed)),
        ].compactMap { $0 }
    }

    // MARK: - Trend

    /// A least-squares line through the points: its value at the first and
    /// last day. Nil under three points, where a line says nothing.
    struct Trend: Equatable {
        let start: (day: Date, value: Double)
        let end: (day: Date, value: Double)

        /// Change from start to end, in percent of the start.
        var change: Double {
            start.value != 0 ? (end.value - start.value) / abs(start.value) * 100 : 0
        }

        static func == (lhs: Trend, rhs: Trend) -> Bool {
            lhs.start.day == rhs.start.day && lhs.start.value == rhs.start.value
                && lhs.end.day == rhs.end.day && lhs.end.value == rhs.end.value
        }
    }

    func trend(_ measure: Measure) -> Trend? {
        let samples = points.compactMap { point in
            point.value(measure).map { (x: point.day.timeIntervalSinceReferenceDate, y: $0) }
        }
        guard samples.count >= 3,
              let first = samples.first, let last = samples.last,
              last.x > first.x
        else { return nil }
        let n = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / n
        let meanY = samples.reduce(0) { $0 + $1.y } / n
        let covariance = samples.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let variance = samples.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        guard variance > 0 else { return nil }
        let slope = covariance / variance
        func at(_ x: Double) -> Double { meanY + slope * (x - meanX) }
        return Trend(
            start: (Date(timeIntervalSinceReferenceDate: first.x), at(first.x)),
            end: (Date(timeIntervalSinceReferenceDate: last.x), at(last.x))
        )
    }
}
