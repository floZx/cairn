import Foundation

/// The training load of each outing, and the fitness, fatigue and form it adds
/// up to — the curves of TrainingPeaks or intervals.icu, in Cairn's terms.
///
/// **The load of one outing** is Edwards' TRIMP: minutes spent in each
/// heart-rate zone, weighted by the zone's number. It is the one load that the
/// data Cairn holds supports honestly — Garmin's five zones, copied as they
/// stood on the day — and it adds across sports, which distance never does.
///
/// Two thirds of the outings predate the zones, though, and leaving them out
/// would draw a fitness that collapses the further back one looks. So an
/// outing without zones is placed from its average heart rate in the zones of
/// the nearest outing that has them, and one without any heart rate is
/// counted as easy. Both are marked `estimated`, so the screen can say how
/// much of the curve rests on them.
///
/// **Fitness, fatigue and form** are the usual exponential averages of the
/// daily load: 42 days for fitness, 7 for fatigue, and form as yesterday's
/// fitness minus yesterday's fatigue — what one carries *into* the day.
enum TrainingLoad {
    struct Load: Equatable {
        let value: Double
        let estimated: Bool
    }

    /// Days over which fitness and fatigue average.
    static let fitnessDays = 42.0
    static let fatigueDays = 7.0

    // MARK: - One outing

    /// The load of one outing.
    ///
    /// - Parameter referenceFloors: the heart-rate zone floors to read an
    ///   average heart rate against when the outing has no zones of its own.
    static func load(of activity: Activity, referenceFloors: [Double]?) -> Load {
        if let seconds = activity.hrZoneSeconds, seconds.reduce(0, +) > 0 {
            let value = seconds.enumerated().reduce(0.0) { sum, zone in
                sum + zone.element / 60 * Double(zone.offset + 1)
            }
            return Load(value: value, estimated: false)
        }
        let minutes = Double(activity.movingTime) / 60
        if let heartrate = activity.averageHeartrate, heartrate > 0,
           let floors = referenceFloors, !floors.isEmpty {
            return Load(
                value: minutes * zoneWeight(heartrate: heartrate, floors: floors),
                estimated: true
            )
        }
        return Load(value: minutes * 1, estimated: true)
    }

    /// The zone an average heart rate falls in, as a continuous weight: 2.5 is
    /// halfway through zone 2.
    ///
    /// Continuous rather than a whole zone number, because an average is not a
    /// zone: a run averaging one beat under the zone-3 floor is not half as
    /// hard as one a beat over it. Below zone 1 the weight shrinks towards
    /// zero, and zone 5 has no ceiling to interpolate towards, so it stays 5.
    static func zoneWeight(heartrate: Double, floors: [Double]) -> Double {
        guard let first = floors.first, heartrate >= first else {
            guard let first = floors.first, first > 0 else { return 1 }
            return max(0, heartrate / first)
        }
        for index in floors.indices.reversed() where heartrate >= floors[index] {
            guard index + 1 < floors.count else { return Double(index + 1) }
            let span = floors[index + 1] - floors[index]
            let fraction = span > 0 ? (heartrate - floors[index]) / span : 0
            return Double(index + 1) + fraction
        }
        return 1
    }

    // MARK: - Day by day

    /// The load of every day that had one, keyed by `ActivityStatistics.day(of:)`.
    struct Daily: Equatable {
        var load: [Date: Double] = [:]
        var movingTime: [Date: Int] = [:]
        /// How many outings were estimated, out of how many.
        var estimatedCount = 0
        var count = 0
    }

    static func daily(_ activities: [Activity]) -> Daily {
        // Zones move over the months, so an outing without its own is read
        // against those of the outing closest to it in time.
        let withZones = activities
            .filter { ($0.hrZoneFloors?.isEmpty == false) }
            .sorted { $0.startDate < $1.startDate }

        func nearestFloors(to date: Date) -> [Double]? {
            guard !withZones.isEmpty else { return nil }
            var low = 0, high = withZones.count
            while low < high {
                let mid = (low + high) / 2
                if withZones[mid].startDate < date { low = mid + 1 } else { high = mid }
            }
            let candidates = [low - 1, low].filter { withZones.indices.contains($0) }
            let best = candidates.min {
                abs(withZones[$0].startDate.timeIntervalSince(date))
                    < abs(withZones[$1].startDate.timeIntervalSince(date))
            }
            return best.flatMap { withZones[$0].hrZoneFloors }
        }

        var result = Daily()
        for activity in activities {
            guard let day = ActivityStatistics.day(of: activity) else { continue }
            let load = load(of: activity, referenceFloors: nearestFloors(to: activity.startDate))
            result.load[day, default: 0] += load.value
            result.movingTime[day, default: 0] += activity.movingTime
            result.count += 1
            if load.estimated { result.estimatedCount += 1 }
        }
        return result
    }

    // MARK: - Fitness, fatigue, form

    struct Point: Identifiable, Equatable {
        let day: Date
        let load: Double
        let fitness: Double
        let fatigue: Double
        /// Yesterday's fitness minus yesterday's fatigue.
        let form: Double

        var id: Date { day }
    }

    /// One point per day, from the first outing to today.
    ///
    /// Computed from the very first outing whatever the window shown: an
    /// exponential average started at zero on the window's first day would
    /// draw a climb that is only the average warming up.
    static func series(
        _ daily: Daily, calendar: Calendar, now: Date = Date()
    ) -> [Point] {
        guard let first = daily.load.keys.min(),
              let today = noon(of: now, calendar: calendar)
        else { return [] }
        var points: [Point] = []
        var fitness = 0.0, fatigue = 0.0
        var day = first
        while day <= today {
            let load = daily.load[day] ?? 0
            let form = fitness - fatigue
            fitness += (load - fitness) / fitnessDays
            fatigue += (load - fatigue) / fatigueDays
            points.append(Point(day: day, load: load, fitness: fitness, fatigue: fatigue, form: form))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    static func noon(of date: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)
    }

    // MARK: - Reading the form

    /// What the form says, in words — the bands intervals.icu uses, relative to
    /// fitness so they mean the same thing at every level of training.
    enum State: Equatable {
        case fresh, neutral, productive, overreaching, detraining

        var label: String {
            switch self {
            case .fresh: "Frais"
            case .neutral: "Équilibré"
            case .productive: "En charge — productif"
            case .overreaching: "Surcharge"
            case .detraining: "Au repos prolongé"
            }
        }

        var advice: String {
            switch self {
            case .fresh: "Reposé : un bon moment pour une sortie clé ou une course."
            case .neutral: "Ni fatigué ni reposé : la charge suit la forme."
            case .productive: "La fatigue dépasse la forme d'assez pour la faire monter."
            case .overreaching: "La fatigue dépasse de loin la forme : du repos s'impose."
            case .detraining: "Très reposé, trop longtemps : la forme redescend."
            }
        }
    }

    static func state(of point: Point) -> State {
        let base = max(point.fitness, 1)
        let ratio = point.form / base
        switch ratio {
        case ..<(-0.3): return .overreaching
        case ..<(-0.1): return .productive
        case ..<0.05: return .neutral
        case ..<0.25: return .fresh
        default: return .detraining
        }
    }

    /// How much fitness moved over the last seven days — the "ramp rate".
    static func ramp(of points: [Point]) -> Double? {
        guard points.count > 7, let last = points.last else { return nil }
        return last.fitness - points[points.count - 8].fitness
    }
}
