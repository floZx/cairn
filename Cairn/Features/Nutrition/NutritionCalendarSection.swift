import SwiftUI
import SwiftData

/// The food journal's calendar, for the sidebar.
///
/// A view of its own rather than a `@Query` on `SidebarView`: the sidebar is on
/// screen in every section, and a query there would fetch every food entry ever
/// logged while one browses activities. Held here, the fetch exists only while
/// the food journal is the section showing — SwiftUI never builds this view
/// otherwise, so the query never runs.
struct NutritionCalendarSection: View {
    @Binding var selected: DateKey

    @Query private var entries: [FoodEntry]
    @Query private var days: [NutritionDay]

    var body: some View {
        let kcalByDay = entries.reduce(into: [String: Double]()) { sums, entry in
            // Rounded per portion, as the day's own figure sums them.
            sums[entry.dateKeyRaw, default: 0] += Macros(of: entry).rounded().kcal
        }
        let targets = days.reduce(into: [String: Int]()) { targets, day in
            if let kcal = day.dayType?.kcalTarget { targets[day.dateKeyRaw] = kcal }
        }
        MiniCalendarView(
            selected: $selected,
            loggedDays: Set(kcalByDay.keys),
            marks: CalorieVerdict.verdicts(kcalByDay: kcalByDay, targets: targets)
                .mapValues(\.color)
        )
    }
}

/// How a day's calories landed against its target — the calorie gauge's
/// colours, one per day, for the calendar. A day under its target, or with
/// no day type, has nothing to say.
enum CalorieVerdict: Equatable {
    case onTarget
    case moderate
    case heavy

    var color: Color {
        switch self {
        case .onTarget: .green
        case .moderate: .orange
        case .heavy: .red
        }
    }

    static func verdicts(
        kcalByDay: [String: Double], targets: [String: Int]
    ) -> [String: CalorieVerdict] {
        kcalByDay.reduce(into: [:]) { verdicts, day in
            guard let target = targets[day.key].map(Double.init) else { return }
            switch NutritionMath.overshoot(consumed: day.value, target: target) {
            case .moderate: verdicts[day.key] = .moderate
            case .heavy: verdicts[day.key] = .heavy
            case nil:
                if NutritionMath.isOnTarget(consumed: day.value, target: target) {
                    verdicts[day.key] = .onTarget
                }
            }
        }
    }
}
