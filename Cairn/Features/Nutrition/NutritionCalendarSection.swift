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
            marks: CalorieVerdict.verdicts(
                kcalByDay: kcalByDay, targets: targets, today: DateKey(Date())
            ).mapValues(\.color)
        )
    }
}

/// How a day's calories landed against its target — the calorie gauge's
/// colours, one per day, for the calendar, plus grey under the target: on a
/// calendar a day without a line read as "no verdict", not as "short". A day
/// with no day type has no target, so nothing to say; today is not short
/// yet, only on target or past it.
enum CalorieVerdict: Equatable {
    case under
    case onTarget
    case moderate
    case heavy

    var color: Color {
        switch self {
        case .under: .gray.opacity(0.5)
        case .onTarget: .green
        case .moderate: .orange
        case .heavy: .red
        }
    }

    static func verdicts(
        kcalByDay: [String: Double], targets: [String: Int], today: DateKey
    ) -> [String: CalorieVerdict] {
        kcalByDay.reduce(into: [:]) { verdicts, day in
            guard let target = targets[day.key].map(Double.init) else { return }
            switch NutritionMath.overshoot(consumed: day.value, target: target) {
            case .moderate: verdicts[day.key] = .moderate
            case .heavy: verdicts[day.key] = .heavy
            case nil:
                if NutritionMath.isOnTarget(consumed: day.value, target: target) {
                    verdicts[day.key] = .onTarget
                } else if day.key != today.raw {
                    verdicts[day.key] = .under
                }
            }
        }
    }
}
