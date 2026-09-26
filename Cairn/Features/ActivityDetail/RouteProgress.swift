import Foundation

/// The figures behind the « Parcours similaires » chart, kept apart from the
/// drawing so they can be checked.
///
/// Speeds in metres per second throughout — the chart plots them, up is
/// faster — but averaged the way a pace is: the mean of the times per
/// kilometre, turned back into a speed. Averaging speeds directly flatters
/// the fast days.
struct RouteProgress: Equatable {
    /// Oldest first.
    let speeds: [Double]
    let fastest: Double
    let slowest: Double
    let average: Double
    /// The trend: each attempt with its neighbours, `window` wide, narrower
    /// at the ends where there are fewer of them.
    let trend: [Double]

    init?(speeds: [Double], window: Int = 5) {
        let valid = speeds.filter { $0 > 0 }
        guard valid.count == speeds.count, speeds.count >= 3,
              let fastest = speeds.max(), let slowest = speeds.min()
        else { return nil }
        self.speeds = speeds
        self.fastest = fastest
        self.slowest = slowest
        average = Self.meanSpeed(speeds)

        let half = window / 2
        trend = speeds.indices.map { index in
            let lower = max(0, index - half)
            let upper = min(speeds.count - 1, index + half)
            return Self.meanSpeed(Array(speeds[lower...upper]))
        }
    }

    /// The speed of the mean pace: 1 ÷ the mean of 1 ÷ speed.
    static func meanSpeed(_ speeds: [Double]) -> Double {
        let pace = speeds.reduce(0) { $0 + 1 / $1 } / Double(speeds.count)
        return 1 / pace
    }

    /// How this attempt compares with the average, said the way the sport
    /// reads it: « 9 s/km plus vite que la moyenne », « 1,2 km/h plus
    /// lent ». Nil when it is the average to the second.
    static func comparison(_ speed: Double, average: Double, sport: SportType) -> String? {
        guard speed > 0, average > 0 else { return nil }
        let faster = speed > average
        let word = faster ? "plus vite" : "plus lent"
        if Format.readsAsPace(sport) {
            let unit: Double = sport == .swim ? 100 : 1000
            let seconds = Int(abs(unit / average - unit / speed).rounded())
            guard seconds > 0 else { return nil }
            let per = sport == .swim ? "/100 m" : "/km"
            let amount = seconds >= 60
                ? String(format: "%d:%02d", seconds / 60, seconds % 60)
                : "\(seconds) s"
            return "\(amount)\(per) \(word) que la moyenne"
        }
        let kmh = abs(speed - average) * 3.6
        guard kmh >= 0.05 else { return nil }
        let amount = String(format: "%.1f", kmh).replacingOccurrences(of: ".", with: ",")
        return "\(amount) km/h \(word) que la moyenne"
    }
}
