import Foundation
import SwiftData

/// Everything the detail-column side panel shows, in one pure pass — the
/// port of suivinut's `stats_panel.stats_lines`, minus the markup.
struct NutritionSidePanelModel: Equatable {
    var averageKcal7d: Int
    var averageProtein7d: Int
    var loggedThisMonth: Int
    var daysElapsedThisMonth: Int
    var streak: Int
    var lastWeightKg: Double?
    var weightDelta7d: Double?
    var weightRatePerWeek: Double?
    var weeksToGoal: Double?

    @MainActor
    static func compute(
        entries: [FoodEntry], weights: [WeightEntry],
        goalKg: Double, day: DateKey
    ) -> NutritionSidePanelModel {
        // Averages over the *logged* days of the trailing week: an empty day
        // is a day off the journal, not a zero that drags the mean down.
        let windowStart = day.advanced(by: -6)
        var totalsByDay: [String: Macros] = [:]
        var loggedDays: Set<String> = []
        for entry in entries {
            loggedDays.insert(entry.dateKeyRaw)
            if entry.dateKeyRaw >= windowStart.raw, entry.dateKeyRaw <= day.raw {
                totalsByDay[entry.dateKeyRaw, default: .zero] =
                    totalsByDay[entry.dateKeyRaw, default: .zero] + Macros(of: entry)
            }
        }
        let dayTotals = Array(totalsByDay.values)
        let loggedCount = dayTotals.count
        let averageKcal = loggedCount == 0
            ? 0
            : Int((dayTotals.map(\.kcal).reduce(0, +) / Double(loggedCount)).rounded())
        let averageProtein = loggedCount == 0
            ? 0
            : Int((dayTotals.map(\.protein).reduce(0, +) / Double(loggedCount)).rounded())

        let monthStart = String(day.raw.prefix(8)) + "01"
        let loggedThisMonth = loggedDays
            .filter { $0 >= monthStart && $0 <= day.raw }.count
        let daysElapsed = Int(day.raw.suffix(2)) ?? 0

        let points = weights
            .compactMap { entry in
                entry.dateKey.map {
                    WeightPoint(dateKey: $0, weightKg: entry.weightKg)
                }
            }
            .sorted { $0.dateKey < $1.dateKey }

        return NutritionSidePanelModel(
            averageKcal7d: averageKcal,
            averageProtein7d: averageProtein,
            loggedThisMonth: loggedThisMonth,
            daysElapsedThisMonth: daysElapsed,
            streak: WeightStats.loggingStreak(loggedDates: loggedDays, endingAt: day),
            lastWeightKg: points.last?.weightKg,
            weightDelta7d: WeightStats.delta(points),
            weightRatePerWeek: WeightStats.ratePerWeek(points),
            weeksToGoal: goalKg > 0
                ? WeightStats.weeksToGoal(points, goal: goalKg) : nil
        )
    }
}
