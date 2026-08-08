import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionDayModel")
@MainActor
struct NutritionDayModelTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("les repas sortent ordonnés avec leurs entrées, totaux et notes")
    func buildsOrderedMeals() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let key = DateKey(raw: "2026-08-08")!
        let oats = FoodEntry(
            dateKey: key, mealSlot: breakfast, foodName: "Flocons",
            kcal100: 370, protein100: 13, carbs100: 60, fat100: 7,
            grams: 100, sortOrder: 1
        )
        let skyr = FoodEntry(
            dateKey: key, mealSlot: breakfast, foodName: "Skyr",
            kcal100: 57, protein100: 10, carbs100: 4, fat100: 0,
            grams: 100, sortOrder: 0
        )
        context.insert(oats)
        context.insert(skyr)
        let note = MealNote(dateKey: key, mealSlot: breakfast, note: "avant footing")
        context.insert(note)
        let dayType = DayType(name: "repos", kcalTarget: 1750)
        context.insert(dayType)

        let model = NutritionDayModel.compute(
            entries: [oats, skyr], slots: [dinner, breakfast], notes: [note],
            dayType: dayType, proteinTargetG: 130, fatTargetG: 66
        )

        #expect(model.dayTypeName == "repos")
        #expect(model.meals.count == 2)
        // Slots ordered by sortOrder even when handed shuffled.
        #expect(model.meals[0].slotName == "Petit-déj")
        // Entries ordered by their own sortOrder: Skyr (0) before Flocons (1).
        #expect(model.meals[0].rows.map(\.name) == ["Skyr", "Flocons"])
        #expect(model.meals[0].note == "avant footing")
        #expect(model.meals[1].rows.isEmpty)
        #expect(model.meals[1].note == nil)
        // 370 + 57 for 100 g each.
        #expect(abs(model.consumed.kcal - 427) < 0.001)
        #expect(abs(model.meals[0].consumed.protein - 23) < 0.001)
    }

    @Test("la cible du jour vient du jour-type et les repas ont leur cible adaptative")
    func computesTargets() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let dayType = DayType(name: "repos", kcalTarget: 2000)
        context.insert(dayType)

        let model = NutritionDayModel.compute(
            entries: [], slots: [breakfast, dinner], notes: [],
            dayType: dayType, proteinTargetG: 100, fatTargetG: 60
        )

        #expect(model.daily?.kcal == 2000)
        // No meal started: each upcoming meal splits the full day pro rata.
        #expect(abs((model.meals[0].target?.kcal ?? 0) - 2000 * 28 / 67) < 0.001)
        #expect(abs((model.meals[1].target?.kcal ?? 0) - 2000 * 39 / 67) < 0.001)
    }

    @Test("sans jour-type : pas de cible du jour ni de cibles de repas")
    func noDayTypeMeansNoTargets() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)

        let model = NutritionDayModel.compute(
            entries: [], slots: [slot], notes: [],
            dayType: nil, proteinTargetG: 130, fatTargetG: 66
        )

        #expect(model.daily == nil)
        #expect(model.meals[0].target == nil)
    }

    @Test("chaque ligne et chaque repas portent l'identité de leur modèle")
    func rowsCarryModelIdentity() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!
        let entry = FoodEntry(
            dateKey: key, mealSlot: slot, foodName: "Skyr",
            kcal100: 57, protein100: 10, carbs100: 4, fat100: 0,
            grams: 150, sortOrder: 0
        )
        context.insert(entry)

        let model = NutritionDayModel.compute(
            entries: [entry], slots: [slot], notes: [],
            dayType: nil, proteinTargetG: 130, fatTargetG: 66
        )
        #expect(model.meals[0].slotID == slot.persistentModelID)
        #expect(model.meals[0].rows[0].entryID == entry.persistentModelID)
    }
}
