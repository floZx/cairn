import Foundation

/// How the period's time splits across heart-rate zones.
///
/// Only outings with Garmin zones count here, unlike the training load: an
/// average heart rate can place an outing's *load* well enough, but it cannot
/// say how its time was spread — an interval session averaging zone 3 spent
/// hardly a minute there. So the card states how many outings it rests on.
struct Intensity: Equatable {
    /// Seconds per zone over the period, zone 1 first.
    let seconds: [Double]
    /// One entry per slot of the period, same slots as the volume chart.
    let slots: [Slot]
    /// Outings with zones, out of all outings in the period.
    let covered: Int
    let count: Int

    struct Slot: Identifiable, Equatable {
        let start: Date
        let seconds: [Double]
        var id: Date { start }
    }

    static let zoneCount = 5

    var total: Double { seconds.reduce(0, +) }

    func share(_ zones: ClosedRange<Int>) -> Double {
        guard total > 0 else { return 0 }
        return zones.reduce(0) { $0 + seconds[$1 - 1] } / total
    }

    /// Zones 1–2, 3, and 4–5: the three bands the polarised model reads.
    var easy: Double { share(1...2) }
    var moderate: Double { share(3...3) }
    var hard: Double { share(4...5) }

    /// What the distribution looks like, in words.
    ///
    /// Polarised is the one the literature favours for endurance — roughly
    /// 80 % easy, little in between, the rest hard. The thresholds below are
    /// the usual rules of thumb, not a verdict.
    enum Profile: Equatable {
        case polarized, pyramidal, threshold, easyOnly

        var label: String {
            switch self {
            case .polarized: "Polarisé"
            case .pyramidal: "Pyramidal"
            case .threshold: "Orienté seuil"
            case .easyOnly: "Presque tout en facile"
            }
        }

        var explanation: String {
            switch self {
            case .polarized: "Beaucoup de facile, du dur, peu d'entre-deux : le modèle des sports d'endurance."
            case .pyramidal: "Surtout du facile, puis de moins en moins à mesure que l'intensité monte."
            case .threshold: "Une grosse part en zone 3 : la « zone grise », fatigante sans être très productive."
            case .easyOnly: "L'intensité manque : quelques séances dures feraient progresser."
            }
        }
    }

    var profile: Profile? {
        guard total > 0 else { return nil }
        if moderate > 0.25 { return .threshold }
        if hard < 0.05 { return .easyOnly }
        return hard > moderate ? .polarized : .pyramidal
    }

    static func compute(
        _ activities: [Activity],
        slotStarts: [Date],
        unit: Calendar.Component
    ) -> Intensity {
        let calendar = ActivityStatistics.calendar
        guard let first = slotStarts.first else { return .empty }
        var totals = Array(repeating: 0.0, count: zoneCount)
        var bySlot: [Date: [Double]] = [:]
        var covered = 0, count = 0
        for activity in activities {
            guard let day = ActivityStatistics.day(of: activity),
                  let slot = calendar.dateInterval(of: unit, for: day)?.start,
                  slot >= first
            else { continue }
            count += 1
            guard let seconds = activity.hrZoneSeconds, seconds.reduce(0, +) > 0 else { continue }
            covered += 1
            var slotTotals = bySlot[slot] ?? Array(repeating: 0, count: zoneCount)
            for (index, value) in seconds.prefix(zoneCount).enumerated() {
                totals[index] += value
                slotTotals[index] += value
            }
            bySlot[slot] = slotTotals
        }
        return Intensity(
            seconds: totals,
            slots: slotStarts.map {
                Slot(start: $0, seconds: bySlot[$0] ?? Array(repeating: 0, count: zoneCount))
            },
            covered: covered,
            count: count
        )
    }

    static let empty = Intensity(seconds: Array(repeating: 0, count: zoneCount), slots: [], covered: 0, count: 0)
}
