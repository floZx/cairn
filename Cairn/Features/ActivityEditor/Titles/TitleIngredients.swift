import CoreLocation
import Foundation

/// What a title can be made of, worked out from what Cairn already holds.
///
/// Pure facts, no phrasing: the same set feeds the on-device model and the
/// templates used without it, so the two can't disagree about the outing —
/// only about how to say it.
struct TitleIngredients: Sendable, Equatable {
    enum PartOfDay: String, Sendable {
        case earlyMorning = "tôt le matin"
        case morning = "le matin"
        case noon = "le midi"
        case afternoon = "l'après-midi"
        case evening = "en soirée"
        case night = "de nuit"

        init(hour: Int) {
            switch hour {
            case 5..<8: self = .earlyMorning
            case 8..<11: self = .morning
            case 11..<14: self = .noon
            case 14..<18: self = .afternoon
            case 18..<22: self = .evening
            default: self = .night
            }
        }
    }

    enum Shape: String, Sendable {
        case loop = "boucle"
        case outAndBack = "aller-retour"
        case pointToPoint = "trajet d'un point à un autre"
    }

    enum Relief: String, Sendable {
        case flat = "plat"
        case rolling = "vallonné"
        case hilly = "très vallonné"
        case mountain = "montagne"
    }

    enum Length: String, Sendable {
        case short = "plus courte que d'habitude"
        case usual = "longueur habituelle"
        case long = "plus longue que d'habitude"
    }

    var sport: SportType
    var weekday: String
    var partOfDay: PartOfDay
    var distanceKm: Double
    var movingMinutes: Int
    var elevationGain: Double
    var relief: Relief?
    var shape: Shape?
    var length: Length?
    /// Communes along the way, start first, without repeats.
    var places: [String] = []
    /// How many earlier outings followed this same course.
    var previousOnRoute: Int = 0
    /// « Seuil 3×12′/2′ », « Côtes 8×45″ », « 12×30″/30″ » — the session,
    /// read in its laps.
    var intervals: String?
    var isRace = false
    var isCommute = false
    var isIndoor = false
    var averageHeartrate: Double?

    var hasDistance: Bool { distanceKm >= 0.1 }

    /// « mercredi midi », « jeudi soir », « samedi matin » — the day and the
    /// moment the way they are said together. « Du mercredi le midi » read
    /// as two phrases stuck end to end.
    var dayAndMoment: String {
        let moment = switch partOfDay {
        case .earlyMorning, .morning: "matin"
        case .noon: "midi"
        case .afternoon: "après-midi"
        case .evening, .night: "soir"
        }
        return "\(weekday) \(moment)"
    }
}

// MARK: - Pure rules

extension TitleIngredients {
    /// Metres of climbing per kilometre, judged by sport: 10 m/km is a hilly
    /// ride but a gentle run.
    static func relief(elevation: Double, distanceKm: Double, sport: SportType) -> Relief? {
        guard distanceKm >= 1 else { return nil }
        let perKm = elevation / distanceKm
        let onWheels: Set<SportType> = [.ride, .mountainBikeRide, .gravelRide, .eBikeRide]
        let (rolling, hilly, mountain): (Double, Double, Double) =
            onWheels.contains(sport) ? (6, 12, 20) : (10, 25, 45)
        switch perKm {
        case ..<rolling: return .flat
        case ..<hilly: return .rolling
        case ..<mountain: return .hilly
        default: return .mountain
        }
    }

    /// Loop when it ends where it began, out-and-back when the way home
    /// retraces the way out, point to point otherwise.
    static func shape(of track: [Coordinate]) -> Shape? {
        guard track.count >= 10, let first = track.first, let last = track.last else {
            return nil
        }
        let farthest = track.map { metres(first, $0) }.max() ?? 0
        guard farthest > 500 else { return nil }
        guard metres(first, last) < max(300, farthest * 0.1) else { return .pointToPoint }

        // Each point against its mirror from the end: on an out-and-back the
        // two are on the same road, on a loop they are on opposite sides.
        let half = track.count / 2
        let gaps = (0..<half).map { metres(track[$0], track[track.count - 1 - $0]) }.sorted()
        let median = gaps[gaps.count / 2]
        return median < max(150, farthest * 0.05) ? .outAndBack : .loop
    }

    static func length(distanceKm: Double, usualKm: Double?) -> Length? {
        guard let usualKm, usualKm > 0, distanceKm > 0 else { return nil }
        let ratio = distanceKm / usualKm
        if ratio >= 1.5 { return .long }
        if ratio <= 0.6 { return .short }
        return .usual
    }

    /// The points worth asking a commune for: the start, then evenly along
    /// the way, the farthest one always among them.
    static func samplePoints(of track: [Coordinate], count: Int = 6) -> [Coordinate] {
        guard let first = track.first else { return [] }
        guard track.count > count else { return track }
        var points = (0..<count).map { track[$0 * (track.count - 1) / (count - 1)] }
        if let farthest = track.max(by: { metres(first, $0) < metres(first, $1) }),
           !points.contains(farthest) {
            points.insert(farthest, at: points.count / 2)
        }
        return points
    }

    static func metres(_ a: Coordinate, _ b: Coordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

// MARK: - Intervals

/// One lap as the interval reader sees it.
struct LapFigures: Sendable, Equatable {
    var distance: Double
    var movingTime: Int
    var averageHeartrate: Double?
    var elevationGain: Double = 0

    var speed: Double { movingTime > 0 ? distance / Double(movingTime) : 0 }
}

enum IntervalReader {
    /// « Seuil 3×12′/2′ », « Côtes 8×45″ », « 12×30″/30″ » when the laps hold
    /// a session of repeats, nil for an outing split every kilometre.
    ///
    /// Written against a real watch, which keeps cutting a lap every
    /// kilometre *during* the repeats: a 12-minute effort arrives as 1000 m,
    /// 1000 m and 787 m. So the fast laps that follow one another are joined
    /// into one effort, and it is the recoveries between them — laps the
    /// workout itself cuts — that mark the repeats.
    static func read(_ all: [LapFigures]) -> String? {
        let laps = all.filter { $0.movingTime > 0 }
        return found(in: laps)?.label
    }

    private static func found(in laps: [LapFigures]) -> Found? {
        guard laps.count >= 3, !isAutoLapOnly(laps) else { return nil }
        let bySpeed = laps.allSatisfy { $0.distance > 0 }
        guard bySpeed || laps.allSatisfy({ $0.averageHeartrate != nil }) else { return nil }
        let intensities = laps.map { bySpeed ? $0.speed : ($0.averageHeartrate ?? 0) }

        // Every cut between slow and fast is tried, and the one kept gives
        // the most regular repeats — then the most of them. The best
        // separated cut went wrong on walked recoveries: so slow that the
        // cut fell between walking and running, and the warm-up joined the
        // first effort, still regular enough to pass at 1,4 km.
        var best: Found?
        for threshold in Set(intensities).sorted().dropFirst() {
            let low = intensities.filter { $0 < threshold }
            let high = intensities.filter { $0 >= threshold }
            // 15 % faster, or 10 bpm higher, on average.
            let apart = bySpeed ? mean(high) >= mean(low) * 1.15 : mean(high) - mean(low) >= 10
            guard apart,
                  let found = repeats(laps, intensities, above: threshold, bySpeed: bySpeed)
            else { continue }
            if best.map({ found.isBetter(than: $0) }) ?? true { best = found }
        }
        return best
    }

    struct Found {
        var label: String
        /// How far the repeats stray from their mean, in the measure named.
        let spread: Double
        let count: Int

        /// Regularity first, to the nearest 2 %; then more repeats.
        func isBetter(than other: Found) -> Bool {
            let mine = (spread * 50).rounded(), theirs = (other.spread * 50).rounded()
            return mine != theirs ? mine < theirs : count > other.count
        }
    }

    /// The repeats found when laps at or above `threshold` count as effort.
    private static func repeats(
        _ laps: [LapFigures], _ intensities: [Double], above threshold: Double, bySpeed: Bool
    ) -> Found? {
        // Consecutive fast laps joined into blocks, and the slow stretches
        // between them kept as the recoveries.
        var efforts: [LapFigures] = []
        var lapCounts: [Int] = []
        var recoveries: [LapFigures] = []
        var current: LapFigures?
        var currentLaps = 0
        var pause: LapFigures?
        for (lap, intensity) in zip(laps, intensities) {
            if intensity >= threshold {
                if let rest = pause, !efforts.isEmpty { recoveries.append(rest) }
                pause = nil
                current = current.map { joined($0, lap) } ?? lap
                currentLaps += 1
            } else {
                if let block = current { efforts.append(block); lapCounts.append(currentLaps) }
                current = nil
                currentLaps = 0
                pause = pause.map { joined($0, lap) } ?? lap
            }
        }
        if let block = current { efforts.append(block); lapCounts.append(currentLaps) }

        // Blocks that are each one kilometre lap of the watch's own are the
        // faster kilometres of an even outing, not repeats.
        let autoLap = laps.filter { abs($0.distance - 1000) <= 10 }.count >= 3
        if autoLap, zip(efforts, lapCounts).allSatisfy({ abs($0.0.distance - 1000) <= 10 && $0.1 == 1 }) {
            return nil
        }

        // A warm-up or cool-down run fast enough to count, at either end,
        // doesn't look like the repeats: set aside when it stands out.
        while efforts.count > 3, let first = efforts.first,
              !alike(first, Array(efforts.dropFirst())) {
            efforts.removeFirst()
            if !recoveries.isEmpty { recoveries.removeFirst() }
        }
        while efforts.count > 3, let last = efforts.last,
              !alike(last, Array(efforts.dropLast())) {
            efforts.removeLast()
            if !recoveries.isEmpty { recoveries.removeLast() }
        }
        // Three at least, of ten seconds at least: two fast stretches of a
        // trail are a descent and another, not a session.
        guard efforts.count >= 3, efforts.allSatisfy({ $0.movingTime >= 10 }) else { return nil }
        return label(
            efforts: efforts, recoveries: Array(recoveries.prefix(efforts.count - 1)),
            bySpeed: bySpeed
        )
    }

    /// Every lap the same length, bar the last: the watch's automatic
    /// kilometre and nothing else — a trail whose downhills run fast.
    private static func isAutoLapOnly(_ laps: [LapFigures]) -> Bool {
        let body = laps.dropLast()
        guard let reference = body.first?.distance, reference > 0 else { return false }
        let same = body.filter { abs($0.distance - reference) <= reference * 0.01 }
        return Double(same.count) >= Double(body.count) * 0.8
    }

    private static func joined(_ a: LapFigures, _ b: LapFigures) -> LapFigures {
        LapFigures(
            distance: a.distance + b.distance, movingTime: a.movingTime + b.movingTime,
            averageHeartrate: a.averageHeartrate, elevationGain: a.elevationGain + b.elevationGain
        )
    }

    /// Whether a block looks like the others, in time or in distance.
    private static func alike(_ block: LapFigures, _ others: [LapFigures]) -> Bool {
        let time = mean(others.map { Double($0.movingTime) })
        let distance = mean(others.map(\.distance))
        let byTime = time > 0 && abs(Double(block.movingTime) - time) / time <= 0.15
        let byDistance = distance > 0 && abs(block.distance - distance) / distance <= 0.1
        return byTime || byDistance
    }

    private static func label(
        efforts: [LapFigures], recoveries: [LapFigures], bySpeed: Bool
    ) -> Found? {
        let times = efforts.map { Double($0.movingTime) }
        let distances = efforts.map(\.distance)
        let timeSpread = spread(times)
        let distanceSpread = bySpeed ? spread(distances) : .infinity
        // Whichever the watch was set to cuts to the second or to the metre:
        // the steadier of the two is what the session was written in.
        let effort: String
        let regularity: Double
        // A tie goes to time: short repeats are set by the clock far more
        // often than by the metre.
        if distanceSpread <= 0.08, distanceSpread < timeSpread {
            effort = distanceLabel(mean(distances))
            regularity = distanceSpread
        } else if timeSpread <= 0.12 {
            effort = durationLabel(mean(times))
            regularity = timeSpread
        } else {
            return nil
        }
        var text = "\(efforts.count)×\(effort)"
        // The recovery too, as it is written by hand — « 5×3′/2′ » — when it
        // was the same every time.
        let rests = recoveries.map { Double($0.movingTime) }
        if rests.count == efforts.count - 1, !rests.isEmpty, spread(rests) <= 0.15 {
            text += "/\(durationLabel(mean(rests)))"
        }
        return Found(label: kind(of: efforts) + text, spread: regularity, count: efforts.count)
    }

    /// Named the way sessions are written by hand: « Côtes » when the
    /// efforts climb — 12 % on a real hill session, next to nothing on the
    /// flat —, « Seuil » from four minutes (a 6×4′ is one, a 5×3′ isn't),
    /// and the repeats alone for the short, fast ones.
    private static func kind(of efforts: [LapFigures]) -> String {
        let distance = efforts.reduce(0) { $0 + $1.distance }
        let climb = efforts.reduce(0) { $0 + $1.elevationGain }
        if distance > 0, climb / distance >= 0.05 { return "Côtes " }
        if mean(efforts.map { Double($0.movingTime) }) >= 230 { return "Seuil " }
        return ""
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    /// Largest gap to the mean, relative to it.
    private static func spread(_ values: [Double]) -> Double {
        let m = mean(values)
        guard m > 0 else { return .infinity }
        return (values.map { abs($0 - m) }.max() ?? 0) / m
    }

    /// Rounded the way a session is written: 400 m, 1 km, 1,5 km.
    private static func distanceLabel(_ metres: Double) -> String {
        if metres < 1000 {
            let step: Double = metres < 300 ? 10 : 50
            return "\(Int((metres / step).rounded() * step)) m"
        }
        let km = (metres / 100).rounded() / 10
        return km == km.rounded()
            ? "\(Int(km)) km"
            : String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }

    /// 45″, 1′, 1′30, 12′ — to the nearest 5 seconds under a minute, to
    /// the nearest quarter minute above.
    private static func durationLabel(_ seconds: Double) -> String {
        let total = Int((seconds / 5).rounded()) * 5
        if total < 60 { return "\(total)″" }
        var minutes = total / 60
        var rest = Int((Double(total % 60) / 15).rounded()) * 15
        if rest == 60 { minutes += 1; rest = 0 }
        return rest == 0 ? "\(minutes)′" : "\(minutes)′\(rest)"
    }
}
