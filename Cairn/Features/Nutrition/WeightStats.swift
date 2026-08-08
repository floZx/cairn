// Cairn/Features/Nutrition/WeightStats.swift
import Foundation

struct WeightPoint: Equatable, Sendable {
    var dateKey: DateKey
    var weightKg: Double
}

/// Pure weight statistics, ported from suivinut's `domain/stats.py` — zero
/// I/O, weigh-ins sorted ascending by date.
enum WeightStats {
    /// The trailing window is anchored on the LAST weigh-in, not on today:
    /// the chart must show data even when the last weigh-in is old.
    static func window(_ weights: [WeightPoint], days: Int?) -> [WeightPoint] {
        guard let days, let last = weights.last else { return weights }
        let cutoff = last.dateKey.advanced(by: -days)
        return weights.filter { $0.dateKey.raw >= cutoff.raw }
    }

    static func delta(_ weights: [WeightPoint], days: Int = 7) -> Double? {
        guard weights.count >= 2 else { return nil }
        let windowed = window(weights, days: days)
        guard windowed.count >= 2, let first = windowed.first,
              let last = windowed.last
        else { return nil }
        return last.weightKg - first.weightKg
    }

    /// Least squares over every point of the window rather than a plain
    /// end-minus-start: an isolated spike at either edge must not fake or
    /// hide a trend.
    static func ratePerWeek(_ weights: [WeightPoint], days: Int = 30) -> Double? {
        guard weights.count >= 2 else { return nil }
        let windowed = window(weights, days: days)
        guard windowed.count >= 2, let origin = windowed.first else { return nil }
        let calendar = Calendar.current
        let start = origin.dateKey.date(calendar: calendar)
        let xs = windowed.map {
            Double(calendar.dateComponents(
                [.day], from: start, to: $0.dateKey.date(calendar: calendar)
            ).day ?? 0)
        }
        let ys = windowed.map(\.weightKg)
        let count = Double(xs.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        let denominator = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard denominator != 0 else { return nil }
        let numerator = zip(xs, ys)
            .map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        return numerator / denominator * 7
    }

    /// nil unless the current rate actually converges on the goal — telling
    /// someone gaining weight "N weeks to your loss goal" would be noise.
    static func weeksToGoal(
        _ weights: [WeightPoint], goal: Double, days: Int = 30
    ) -> Double? {
        guard let last = weights.last,
              let rate = ratePerWeek(weights, days: days)
        else { return nil }
        let remaining = last.weightKg - goal
        guard remaining != 0, rate != 0, (remaining > 0) != (rate > 0) else {
            return nil
        }
        return abs(remaining / rate)
    }

    static func loggingStreak(
        loggedDates: Set<String>, endingAt end: DateKey
    ) -> Int {
        var day = end
        var streak = 0
        while loggedDates.contains(day.raw) {
            streak += 1
            day = day.advanced(by: -1)
        }
        return streak
    }
}
