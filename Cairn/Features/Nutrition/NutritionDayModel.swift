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
        /// What the target above *means*, which is not the same for every
        /// meal of a day — and which nothing on screen said until a reader
        /// added three of them up and asked where the error was.
        var targetKind: TargetKind = .remaining
        /// The meal's share of the day, in percent. In the tooltip, because a
        /// share is what makes a plan figure readable as one.
        var pct: Int = 0
    }

    /// A finished meal keeps its share of the plan, so it can be compared to
    /// it; the meal in progress and those to come split what is really left.
    /// Hence three targets that do not add up to the day's, on purpose.
    enum TargetKind: Equatable {
        case planShare
        case remaining
    }

    var dayTypeName: String?
    var daily: Macros?
    var consumed: Macros
    /// Les fibres du jour, et le nombre d'aliments qui n'en annoncent pas.
    var fiber: FiberTally
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
        // Rounded per portion, then summed: what a row shows is what it adds
        // to its meal. See `Macros.rounded()`.
        let mealConsumed = mealEntries.map { entries in
            entries.map { Macros(of: $0).rounded() }.reduce(.zero, +)
        }
        // Sommées sur les valeurs exactes, puis arrondies une fois à
        // l'affichage — au contraire des macros, arrondies par portion.
        // La règle des macros existe pour qu'une colonne de chiffres
        // s'additionne à son total ; les fibres n'ont pas de colonne, aucune
        // ligne de repas ne les montre. Les arrondir par portion ne servirait
        // donc personne et effacerait les contributions sous le demi-gramme,
        // dont une journée compte beaucoup.
        let fiber = entries.map { FiberTally(of: $0) }.reduce(.zero, +)
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
        let states = zip(orderedSlots, zip(mealEntries, mealConsumed)).map {
            slot, pair in
            NutritionMath.MealState(
                pct: slot.targetPct, started: !pair.0.isEmpty, consumed: pair.1
            )
        }
        let finished = NutritionMath.superseded(in: states)
        let meals = orderedSlots.enumerated().map { index, slot in
            Meal(
                slotID: slot.persistentModelID,
                slotName: slot.name,
                rows: mealEntries[index].map {
                    Row(
                        entryID: $0.persistentModelID, name: $0.foodName,
                        grams: $0.grams, macros: Macros(of: $0).rounded(),
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
                }?.note,
                targetKind: finished[index] ? .planShare : .remaining,
                pct: slot.targetPct
            )
        }
        return NutritionDayModel(
            dayTypeName: dayType?.name,
            daily: daily,
            consumed: mealConsumed.reduce(.zero, +),
            fiber: fiber,
            meals: meals
        )
    }
}
