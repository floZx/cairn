import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Modèles nutrition")
@MainActor
struct NutritionModelsTests {
    @Test("une journée complète survit à un aller-retour en base")
    func persistsAFullDay() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let dayType = DayType(name: "sortie longue", kcalTarget: 2500, sortOrder: 3)
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let day = NutritionDay(dateKey: DateKey(raw: "2026-08-08")!, dayType: dayType)
        let entry = FoodEntry(
            dateKey: DateKey(raw: "2026-08-08")!, mealSlot: slot,
            foodName: "Flocons d'avoine", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80, sortOrder: 0
        )
        let note = MealNote(
            dateKey: DateKey(raw: "2026-08-08")!, mealSlot: slot, note: "avant footing"
        )
        let weight = WeightEntry(dateKey: DateKey(raw: "2026-08-08")!, weightKg: 71.2)
        context.insert(dayType)
        context.insert(slot)
        context.insert(day)
        context.insert(entry)
        context.insert(note)
        context.insert(weight)
        try context.save()

        let fetchedDays = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(fetchedDays.count == 1)
        #expect(fetchedDays[0].dayType?.name == "sortie longue")
        #expect(fetchedDays[0].dateKey?.raw == "2026-08-08")
        let fetchedEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(fetchedEntries.count == 1)
        #expect(fetchedEntries[0].mealSlot?.name == "Petit-déj")
        #expect(fetchedEntries[0].kcal100 == 370)
        let fetchedNotes = try context.fetch(FetchDescriptor<MealNote>())
        #expect(fetchedNotes[0].note == "avant footing")
        let fetchedWeights = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(fetchedWeights[0].weightKg == 71.2)
    }

    @Test("une recette et ses items se suppriment en cascade")
    func recipeCascadesToItems() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let recipe = Recipe(name: "Porridge")
        let item = RecipeItem(
            foodName: "Flocons", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80
        )
        item.recipe = recipe
        context.insert(recipe)
        context.insert(item)
        try context.save()

        context.delete(recipe)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<RecipeItem>()).isEmpty)
    }

    @Test("un favori persiste ses macros dénormalisées")
    func persistsFavorite() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let favorite = FavoriteFood(
            foodName: "Skyr", kcal100: 57, protein100: 10,
            carbs100: 4, fat100: 0.2, grams: 150
        )
        context.insert(favorite)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<FavoriteFood>())
        #expect(fetched[0].protein100 == 10)
        #expect(fetched[0].grams == 150)
    }
}
