import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionJournal")
@MainActor
struct NutritionJournalTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func addFood(
        _ name: String, to slot: MealSlot, context: ModelContext,
        dateKey: DateKey = DateKey(raw: "2026-08-08")!
    ) throws -> FoodEntry {
        try NutritionJournal.addEntry(
            in: context, dateKey: dateKey, slot: slot, foodName: name,
            kcal100: 100, protein100: 10, carbs100: 20, fat100: 5, grams: 100
        )
    }

    @Test("une nouvelle entrée s'ajoute en fin de son repas")
    func appendsAtEndOfMeal() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)

        let first = try addFood("A", to: breakfast, context: context)
        let second = try addFood("B", to: breakfast, context: context)
        let other = try addFood("C", to: dinner, context: context)

        #expect(first.sortOrder < second.sortOrder)
        // Le compteur est par (date, repas) : le dîner repart de son propre max.
        #expect(other.sortOrder <= second.sortOrder)
        let saved = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(saved.count == 3)
    }

    @Test("un aliment ajouté sous une ligne se place juste après elle")
    func insertsUnderTheAnchor() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let a = try addFood("A", to: slot, context: context)
        let b = try addFood("B", to: slot, context: context)

        let inserted = try NutritionJournal.addEntry(
            in: context, dateKey: DateKey(raw: "2026-08-08")!, slot: slot,
            foodName: "A bis", kcal100: 100, protein100: 10, carbs100: 20,
            fat100: 5, grams: 100, after: a
        )

        let order = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.foodName)
        #expect(order == ["A", "A bis", "B"])
        // Le repas est renuméroté d'un bloc, sans trou où glisser deux fois.
        let renumbered: [Int] = [a.sortOrder, inserted.sortOrder, b.sortOrder]
        #expect(renumbered == [0, 1, 2])
    }

    @Test("une ancre d'un autre repas laisse l'ajout en fin de repas")
    func ignoresAnAnchorFromAnotherMeal() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let elsewhere = try addFood("A", to: breakfast, context: context)
        let first = try addFood("B", to: dinner, context: context)

        let added = try NutritionJournal.addEntry(
            in: context, dateKey: DateKey(raw: "2026-08-08")!, slot: dinner,
            foodName: "C", kcal100: 100, protein100: 10, carbs100: 20,
            fat100: 5, grams: 100, after: elsewhere
        )

        #expect(first.sortOrder < added.sortOrder)
    }

    @Test("monter échange avec le voisin du dessus, no-op en tête")
    func moveUpSwapsWithNeighbour() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let a = try addFood("A", to: slot, context: context)
        let b = try addFood("B", to: slot, context: context)

        try NutritionJournal.move(b, direction: -1, in: context)
        #expect(b.sortOrder < a.sortOrder)

        // B est en tête : remonter encore ne change rien.
        let before = (b.sortOrder, a.sortOrder)
        try NutritionJournal.move(b, direction: -1, in: context)
        #expect((b.sortOrder, a.sortOrder) == before)
    }

    @Test("descendre ne franchit jamais la frontière du repas")
    func moveDownStaysInMeal() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let a = try addFood("A", to: breakfast, context: context)
        _ = try addFood("B", to: dinner, context: context)

        // A est seul dans son repas : descendre est un no-op même si le
        // dîner contient une entrée au sortOrder supérieur.
        let before = a.sortOrder
        try NutritionJournal.move(a, direction: 1, in: context)
        #expect(a.sortOrder == before)
    }

    @Test("le déplacement ignore les entrées d'une autre date")
    func moveIgnoresOtherDates() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let today = try addFood("A", to: slot, context: context)
        _ = try addFood(
            "Hier", to: slot, context: context,
            dateKey: DateKey(raw: "2026-08-07")!
        )

        let before = today.sortOrder
        try NutritionJournal.move(today, direction: -1, in: context)
        #expect(today.sortOrder == before)
    }

    @Test("l'édition ne touche que le libellé et les grammes")
    func updateKeepsMacros() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let entry = try addFood("A", to: slot, context: context)

        try NutritionJournal.update(
            entry, foodName: "Avoine bio", grams: 55, in: context
        )
        #expect(entry.foodName == "Avoine bio")
        #expect(entry.grams == 55)
        #expect(entry.kcal100 == 100)
        #expect(entry.protein100 == 10)
    }

    @Test("la suppression retire l'entrée du store")
    func deleteRemoves() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let entry = try addFood("A", to: slot, context: context)

        try NutritionJournal.delete(entry, in: context)
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).isEmpty)
    }

    @Test("le jour-type s'upsert sur la date")
    func dayTypeUpserts() throws {
        let context = try makeContext()
        let rest = DayType(name: "repos", kcalTarget: 1800)
        let long = DayType(name: "sortie longue", kcalTarget: 2500)
        context.insert(rest)
        context.insert(long)
        let key = DateKey(raw: "2026-08-08")!

        try NutritionJournal.setDayType(rest, for: key, in: context)
        var days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType?.name == "repos")

        try NutritionJournal.setDayType(long, for: key, in: context)
        days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType?.name == "sortie longue")

        try NutritionJournal.setDayType(nil, for: key, in: context)
        days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType == nil)
    }

    @Test("une note s'upsert, une note vide se supprime")
    func mealNoteUpsertsAndClears() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!

        try NutritionJournal.setMealNote("avant footing", for: key, slot: slot, in: context)
        var notes = try context.fetch(FetchDescriptor<MealNote>())
        #expect(notes.count == 1)
        #expect(notes[0].note == "avant footing")

        try NutritionJournal.setMealNote("  après footing  ", for: key, slot: slot, in: context)
        notes = try context.fetch(FetchDescriptor<MealNote>())
        #expect(notes.count == 1)
        #expect(notes[0].note == "après footing")

        try NutritionJournal.setMealNote("   ", for: key, slot: slot, in: context)
        #expect(try context.fetch(FetchDescriptor<MealNote>()).isEmpty)
    }

    @Test("la bascule favori ajoute puis retire, clé (nom, code)")
    func favoriteToggles() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let entry = try addFood("Skyr", to: slot, context: context)

        #expect(try NutritionJournal.toggleFavorite(for: entry, in: context))
        var favorites = try context.fetch(FetchDescriptor<FavoriteFood>())
        #expect(favorites.count == 1)
        #expect(favorites[0].foodName == "Skyr")
        #expect(favorites[0].grams == 100)
        #expect(try NutritionJournal.favoriteKeys(in: context)
            == [FavoriteKey(foodName: "Skyr", productCode: nil)])

        #expect(try NutritionJournal.toggleFavorite(for: entry, in: context) == false)
        #expect(try context.fetch(FetchDescriptor<FavoriteFood>()).isEmpty)
    }

    @Test("deux favoris de même nom mais code différent coexistent")
    func favoriteKeyIncludesCode() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let generic = try addFood("Riz", to: slot, context: context)
        let branded = try NutritionJournal.addEntry(
            in: context, dateKey: DateKey(raw: "2026-08-08")!, slot: slot,
            foodName: "Riz", kcal100: 350, protein100: 7, carbs100: 77,
            fat100: 1, grams: 120, productCode: "123"
        )

        try NutritionJournal.toggleFavorite(for: generic, in: context)
        try NutritionJournal.toggleFavorite(for: branded, in: context)
        #expect(try context.fetch(FetchDescriptor<FavoriteFood>()).count == 2)

        // Retirer le favori générique laisse le favori de marque en place.
        try NutritionJournal.toggleFavorite(for: generic, in: context)
        let remaining = try context.fetch(FetchDescriptor<FavoriteFood>())
        #expect(remaining.count == 1)
        #expect(remaining[0].productCode == "123")
    }

    @Test("removeFavorite supprime le favori visé")
    func removeFavoriteDeletes() throws {
        let context = try makeContext()
        let favorite = FavoriteFood(
            foodName: "Skyr", kcal100: 57, protein100: 10,
            carbs100: 4, fat100: 0.2, grams: 150
        )
        context.insert(favorite)
        try context.save()
        try NutritionJournal.removeFavorite(favorite, in: context)
        #expect(try context.fetch(FetchDescriptor<FavoriteFood>()).isEmpty)
    }

    @Test("appliquer une recette appende ses items en fin de repas, dans l'ordre")
    func applyRecipeAppendsInOrder() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!
        _ = try addFood("Déjà là", to: slot, context: context)

        let recipe = Recipe(name: "Porridge", mealSlot: slot)
        context.insert(recipe)
        let oats = RecipeItem(
            foodName: "Flocons", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80
        )
        oats.sortOrder = 0
        oats.recipe = recipe
        let milk = RecipeItem(
            foodName: "Lait", kcal100: 47, protein100: 3.2,
            carbs100: 4.8, fat100: 1.5, grams: 200, productCode: "456"
        )
        milk.sortOrder = 1
        milk.recipe = recipe
        context.insert(oats)
        context.insert(milk)
        try context.save()

        try NutritionJournal.applyRecipe(recipe, to: key, slot: slot, in: context)

        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(entries.map(\.foodName) == ["Déjà là", "Flocons", "Lait"])
        #expect(entries[2].productCode == "456")
        #expect(entries[1].kcal100 == 370)
    }

    @Test("enregistrer un repas comme recette copie ses entrées dans l'ordre")
    func saveMealAsRecipeCopiesEntries() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!
        _ = try addFood("Skyr", to: slot, context: context, dateKey: key)
        _ = try addFood("Granola", to: slot, context: context, dateKey: key)
        // Une entrée d'un autre jour ne doit pas entrer dans la recette.
        _ = try addFood(
            "Hier", to: slot, context: context, dateKey: DateKey(raw: "2026-08-07")!
        )

        let recipe = try NutritionJournal.saveMealAsRecipe(
            named: "Petit-déj type", dateKey: key, slot: slot, in: context
        )
        #expect(recipe.mealSlot?.persistentModelID == slot.persistentModelID)
        #expect(recipe.orderedItems.map(\.foodName) == ["Skyr", "Granola"])
        #expect(recipe.orderedItems[0].grams == 100)
    }

    @Test("enregistrer un repas vide comme recette échoue")
    func saveEmptyMealThrows() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        #expect(throws: (any Error).self) {
            try NutritionJournal.saveMealAsRecipe(
                named: "Vide", dateKey: DateKey(raw: "2026-08-08")!,
                slot: slot, in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
    }

    @Test("ajout et suppression d'items de recette, ordre stable")
    func recipeItemCrud() throws {
        let context = try makeContext()
        let recipe = Recipe(name: "Porridge")
        context.insert(recipe)
        try context.save()

        let first = try NutritionJournal.addRecipeItem(
            to: recipe, foodName: "Flocons", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80, productCode: nil, in: context
        )
        _ = try NutritionJournal.addRecipeItem(
            to: recipe, foodName: "Lait", kcal100: 47, protein100: 3.2,
            carbs100: 4.8, fat100: 1.5, grams: 200, productCode: nil, in: context
        )
        #expect(recipe.orderedItems.map(\.foodName) == ["Flocons", "Lait"])

        try NutritionJournal.deleteRecipeItem(first, in: context)
        #expect(recipe.orderedItems.map(\.foodName) == ["Lait"])

        try NutritionJournal.deleteRecipe(recipe, in: context)
        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecipeItem>()).isEmpty)
    }

    @Test("un jour-type s'ajoute en fin d'ordre et se supprime sans casser les jours")
    func dayTypeCrud() throws {
        let context = try makeContext()
        let first = try NutritionJournal.addDayType(
            named: "repos", kcalTarget: 1800, in: context
        )
        let second = try NutritionJournal.addDayType(
            named: "qualité", kcalTarget: 2100, in: context
        )
        #expect(first.sortOrder < second.sortOrder)

        // Un jour qui référence le type supprimé garde sa ligne, type effacé.
        let key = DateKey(raw: "2026-08-08")!
        try NutritionJournal.setDayType(second, for: key, in: context)
        try NutritionJournal.deleteDayType(second, in: context)
        let days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType == nil)
        #expect(try context.fetch(FetchDescriptor<DayType>()).count == 1)
    }

    @Test("un jour-type se déplace dans la liste, et l'ordre est renuméroté")
    func dayTypeReordering() throws {
        let context = try makeContext()
        let names = ["repos", "qualité", "sortie longue"]
        for name in names {
            _ = try NutritionJournal.addDayType(
                named: name, kcalTarget: 2000, in: context
            )
        }
        func ordered() throws -> [String] {
            try context.fetch(FetchDescriptor<DayType>())
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.name)
        }
        let last = try #require(
            try context.fetch(FetchDescriptor<DayType>())
                .first { $0.name == "sortie longue" }
        )
        try NutritionJournal.moveDayType(last, by: -1, in: context)
        #expect(try ordered() == ["repos", "sortie longue", "qualité"])
        // Renumérotés de 0 à n-1 : un ordre à trous ferait retomber le
        // prochain ajout au milieu de la liste.
        #expect(
            try context.fetch(FetchDescriptor<DayType>())
                .map(\.sortOrder).sorted() == [0, 1, 2]
        )
        // Aux extrémités, le déplacement ne fait rien plutôt que de boucler.
        let first = try #require(
            try context.fetch(FetchDescriptor<DayType>())
                .first { $0.name == "repos" }
        )
        try NutritionJournal.moveDayType(first, by: -1, in: context)
        #expect(try ordered() == ["repos", "sortie longue", "qualité"])
    }

    @Test("une pesée par jour : ressaisir remplace")
    func weightUpsertsPerDay() throws {
        let context = try makeContext()
        let key = DateKey(raw: "2026-08-08")!

        try NutritionJournal.recordWeight(71.4, note: "matin", for: key, in: context)
        try NutritionJournal.recordWeight(71.2, note: nil, for: key, in: context)

        let entries = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].weightKg == 71.2)
        #expect(entries[0].note == nil)
    }

    @Test("la note d'une pesée se vide en nil après trim")
    func weightNoteTrimsToNil() throws {
        let context = try makeContext()
        let entry = try NutritionJournal.recordWeight(
            70.9, note: "   ", for: DateKey(raw: "2026-08-07")!, in: context
        )
        #expect(entry.note == nil)
    }

    @Test("la suppression d'une pesée retire sa ligne")
    func weightDeletes() throws {
        let context = try makeContext()
        let entry = try NutritionJournal.recordWeight(
            71.0, note: nil, for: DateKey(raw: "2026-08-08")!, in: context
        )
        try NutritionJournal.deleteWeight(entry, in: context)
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).isEmpty)
    }

    @Test("placer après renumérote tout le repas")
    func placeAfterRenumbers() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let a = try addFood("A", to: slot, context: context)
        let b = try addFood("B", to: slot, context: context)
        let c = try addFood("C", to: slot, context: context)

        // A après C : ordre B, C, A — et des sort_order 0,1,2 propres.
        try NutritionJournal.placeEntry(a, after: c, in: context)
        let ordered = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.foodName) == ["B", "C", "A"])
        #expect(ordered.map(\.sortOrder) == [0, 1, 2])

        // C après A : B, A, C.
        try NutritionJournal.placeEntry(c, after: a, in: context)
        let again = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(again.map(\.foodName) == ["B", "A", "C"])
    }

    @Test("placer après une cible d'un autre repas est sans effet")
    func placeAcrossMealsIsNoOp() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let a = try addFood("A", to: breakfast, context: context)
        let d = try addFood("D", to: dinner, context: context)

        let before = (a.sortOrder, a.mealSlot?.name)
        try NutritionJournal.placeEntry(a, after: d, in: context)
        #expect((a.sortOrder, a.mealSlot?.name) == before)
    }

    @Test("appliquer une recette n'écrit qu'une fois")
    func applyRecipeSavesOnce() throws {
        // Pas d'espion de save() : on vérifie l'invariant observable — les
        // sort_order restent contigus et l'ordre est bon, comme avant.
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let recipe = Recipe(name: "R", mealSlot: slot)
        context.insert(recipe)
        for (index, name) in ["Un", "Deux", "Trois"].enumerated() {
            let item = RecipeItem(
                foodName: name, kcal100: 100, protein100: 1,
                carbs100: 1, fat100: 1, grams: 100
            )
            item.sortOrder = index
            item.recipe = recipe
            context.insert(item)
        }
        try context.save()
        try NutritionJournal.applyRecipe(
            recipe, to: DateKey(raw: "2026-08-08")!, slot: slot, in: context
        )
        let ordered = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.foodName) == ["Un", "Deux", "Trois"])
        #expect(context.hasChanges == false)
    }
}

@Suite("L'ordre des ingrédients d'une recette")
@MainActor
struct RecipeItemOrderTests {
    private func makeRecipe(in context: ModelContext, foods: [String]) -> Recipe {
        let recipe = Recipe(name: "Bol du matin")
        context.insert(recipe)
        for (index, name) in foods.enumerated() {
            let item = RecipeItem(
                foodName: name, kcal100: 100, protein100: 10, carbs100: 20,
                fat100: 5, grams: 100
            )
            item.sortOrder = index
            item.recipe = recipe
            context.insert(item)
        }
        return recipe
    }

    @Test("monter un ingrédient échange sa place avec celui du dessus")
    func movingUpSwapsWithTheOneAbove() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let recipe = makeRecipe(in: context, foods: ["Flocons", "Skyr", "Miel"])
        let skyr = recipe.orderedItems[1]

        try NutritionJournal.moveRecipeItem(skyr, direction: -1, in: context)
        #expect(recipe.orderedItems.map(\.foodName) == ["Skyr", "Flocons", "Miel"])
    }

    @Test("aux extrémités, rien ne bouge")
    func theedgesHold() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let recipe = makeRecipe(in: context, foods: ["Flocons", "Skyr"])

        try NutritionJournal.moveRecipeItem(
            recipe.orderedItems[0], direction: -1, in: context
        )
        #expect(recipe.orderedItems.map(\.foodName) == ["Flocons", "Skyr"])
        try NutritionJournal.moveRecipeItem(
            recipe.orderedItems[1], direction: 1, in: context
        )
        #expect(recipe.orderedItems.map(\.foodName) == ["Flocons", "Skyr"])
    }

    @Test("des ingrédients tous à zéro se renumérotent au lieu de s'échanger")
    func itemsAllAtZeroAreRenumbered() throws {
        // Ceux importés avant l'existence de `sortOrder` valent tous 0 : un
        // échange de deux zéros ne déplacerait rien.
        let context = ModelContext(try AppModelContainer.inMemory())
        let recipe = makeRecipe(in: context, foods: ["Ail", "Basilic", "Cumin"])
        for item in recipe.orderedItems { item.sortOrder = 0 }

        // À égalité, l'ordre est alphabétique — c'est le repli du modèle.
        #expect(recipe.orderedItems.map(\.foodName) == ["Ail", "Basilic", "Cumin"])
        try NutritionJournal.moveRecipeItem(
            recipe.orderedItems[2], direction: -1, in: context
        )
        #expect(recipe.orderedItems.map(\.foodName) == ["Ail", "Cumin", "Basilic"])
    }
}
