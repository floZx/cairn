import Foundation
import SwiftData

/// Everything the day screen shows, computed in one pure pass — the same
/// split as `ActivityStatistics`: the view stays declarative, the arithmetic
/// stays testable without UI.
struct NutritionDayModel: Equatable {
    struct Row: Equatable {
        var entryID: PersistentIdentifier
        var name: String
        var grams: Double
        var macros: Macros
        var isFavorite: Bool
    }

    struct Meal: Equatable {
        var slotID: PersistentIdentifier
        var slotName: String
        var rows: [Row]
        var consumed: Macros
        var target: Macros?
        var note: String?
    }

    var dayTypeName: String?
    var daily: Macros?
    var consumed: Macros
    var meals: [Meal]

    @MainActor
    static func compute(
        entries: [FoodEntry], slots: [MealSlot], notes: [MealNote],
        dayType: DayType?, proteinTargetG: Double, fatTargetG: Double,
        favoriteKeys: Set<FavoriteKey>
    ) -> NutritionDayModel {
        let orderedSlots = slots.sorted { $0.sortOrder < $1.sortOrder }
        // Grouped by object identity: entries reference the slot itself, so
        // no id juggling is needed.
        let entriesBySlot = Dictionary(grouping: entries) {
            $0.mealSlot?.persistentModelID
        }
        let daily = NutritionMath.dailyTargets(
            kcalTarget: dayType?.kcalTarget,
            proteinG: proteinTargetG, fatG: fatTargetG
        )
        let mealEntries = orderedSlots.map { slot in
            (entriesBySlot[slot.persistentModelID] ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
        }
        let mealConsumed = mealEntries.map { entries in
            entries.map(Macros.init(of:)).reduce(.zero, +)
        }
        let targets = NutritionMath.adaptiveMealTargets(
            daily: daily,
            meals: zip(orderedSlots, zip(mealEntries, mealConsumed)).map {
                slot, pair in
                NutritionMath.MealState(
                    pct: slot.targetPct, started: !pair.0.isEmpty,
                    consumed: pair.1
                )
            }
        )
        let meals = orderedSlots.enumerated().map { index, slot in
            Meal(
                slotID: slot.persistentModelID,
                slotName: slot.name,
                rows: mealEntries[index].map {
                    Row(
                        entryID: $0.persistentModelID, name: $0.foodName,
                        grams: $0.grams, macros: Macros(of: $0),
                        isFavorite: favoriteKeys.contains(
                            FavoriteKey(
                                foodName: $0.foodName, productCode: $0.productCode
                            )
                        )
                    )
                },
                consumed: mealConsumed[index],
                target: targets[index],
                note: notes.first {
                    $0.mealSlot?.persistentModelID == slot.persistentModelID
                }?.note
            )
        }
        return NutritionDayModel(
            dayTypeName: dayType?.name,
            daily: daily,
            consumed: mealConsumed.reduce(.zero, +),
            meals: meals
        )
    }
}
