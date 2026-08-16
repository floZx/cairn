import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Identités du miroir")
struct MirrorIdentityTests {
    /// Chaque modèle naît avec un identifiant à lui, et deux instances n'en
    /// partagent jamais un : c'est la seule chose qui rendra une ligne
    /// reconnaissable d'un magasin à l'autre.
    @Test func chaqueModeleNaitAvecUnIdentifiant() throws {
        let first = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        let second = WeightEntry(dateKey: DateKey(raw: "2026-08-17")!, weightKg: 71)

        #expect(!first.uuid.isEmpty)
        #expect(first.uuid != second.uuid)
    }

    /// Une ligne écrite puis relue garde le même identifiant. Un `uuid`
    /// recalculé à la lecture ne serait pas une identité.
    @Test func lIdentifiantSurvitAuDisque() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        let expected = entry.uuid
        context.insert(entry)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.uuid == expected)
    }

    /// Les seize types qui traversent vers le miroir — `AppModelContainer.schema`
    /// moins `SyncState`, qui décrit la relation avec Strava et ne traverse pas
    /// — portent chacun un identifiant à la création, et aucun des seize ne
    /// partage le sien avec un autre. Un compte sur l'ensemble plutôt qu'un
    /// modèle choisi au hasard : c'est un modèle oublié de cette liste,
    /// `ActivityPhoto`, qui a d'abord échappé à la vérification.
    @Test func lesSeizeModelesQuiTraversentOntTousUnIdentifiant() throws {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        let activityStreams = ActivityStreams()
        let activityPhoto = ActivityPhoto(uniqueID: "strava-photo-1")
        let athlete = Athlete(stravaID: 1)
        let lap = Lap(stravaID: 1, lapIndex: 0)
        let gear = Gear(stravaID: "b1", name: "Vélo")
        let discardedActivity = DiscardedActivity(stravaID: 1, name: "Sortie annulée")
        let dayType = DayType(name: "Repos", kcalTarget: 2000)
        let mealSlot = MealSlot(name: "Petit-déj")
        let nutritionDay = NutritionDay(dateKey: DateKey(raw: "2026-08-16")!)
        let foodEntry = FoodEntry(
            dateKey: DateKey(raw: "2026-08-16")!, mealSlot: nil, foodName: "Pomme",
            kcal100: 52, protein100: 0.3, carbs100: 14, fat100: 0.2, grams: 150
        )
        let mealNote = MealNote(dateKey: DateKey(raw: "2026-08-16")!, mealSlot: nil, note: "Bon appétit")
        let recipe = Recipe(name: "Porridge")
        let recipeItem = RecipeItem(
            foodName: "Flocons d'avoine", kcal100: 389, protein100: 13, carbs100: 66, fat100: 7, grams: 80
        )
        let favoriteFood = FavoriteFood(
            foodName: "Banane", kcal100: 89, protein100: 1.1, carbs100: 23, fat100: 0.3, grams: 120
        )
        let weightEntry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)

        let uuids = [
            activity.uuid, activityStreams.uuid, activityPhoto.uuid, athlete.uuid,
            lap.uuid, gear.uuid, discardedActivity.uuid, dayType.uuid, mealSlot.uuid,
            nutritionDay.uuid, foodEntry.uuid, mealNote.uuid, recipe.uuid,
            recipeItem.uuid, favoriteFood.uuid, weightEntry.uuid,
        ]

        #expect(uuids.count == 16)
        #expect(uuids.allSatisfy { !$0.isEmpty })
        #expect(Set(uuids).count == uuids.count)
    }
}
