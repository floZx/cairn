import Foundation
import SwiftData

/// The starter journal for someone who skips the suivinut import — the same
/// defaults as suivinut's `_seed()`, so both starting points feel identical.
enum NutritionSeed {
    @MainActor
    static func runIfEmpty(in context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<MealSlot>()).isEmpty else {
            return
        }
        let slots = [
            ("Petit-déj", 28), ("Déjeuner", 33), ("Collation", 0), ("Dîner", 39),
        ]
        for (index, slot) in slots.enumerated() {
            context.insert(
                MealSlot(name: slot.0, sortOrder: index, targetPct: slot.1)
            )
        }
        let dayTypes = [
            ("repos", 1800), ("lever", 1900), ("qualité", 2100),
            ("sortie longue", 2500),
        ]
        for (index, dayType) in dayTypes.enumerated() {
            context.insert(
                DayType(
                    name: dayType.0, kcalTarget: dayType.1, sortOrder: index
                )
            )
        }
        try context.save()
    }
}
