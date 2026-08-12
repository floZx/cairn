import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Le bloc alimentation du volet du journal")
@MainActor
struct JournalDayNutritionTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("la note d'un repas est annoncée par le repas")
    func amealNoteIsNamedByItsMeal() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let note = MealNote(dateKey: key("2026-08-12"), mealSlot: lunch, note: "Sushi.")
        context.insert(note)

        #expect(JournalDayNutrition.label(for: note) == "Déjeuner")
    }

    @Test("un repas disparu ne laisse pas d'étiquette vide")
    func aslotlessNoteKeepsAName() throws {
        let context = try makeContext()
        let orphan = MealNote(dateKey: key("2026-08-12"), mealSlot: nil, note: "Sushi.")
        context.insert(orphan)

        // Supprimer un repas dans les réglages laisse ses notes derrière lui ;
        // une puce sans nom serait plus déroutante qu'un mot générique.
        #expect(JournalDayNutrition.label(for: orphan) == "Repas")
    }

    @Test("la pesée s'écrit avec sa virgule et son unité")
    func theweighInReadsAsAWeight() throws {
        let context = try makeContext()
        let entry = WeightEntry(
            dateKey: key("2026-08-12"), weightKg: 70.2, note: "Bien dormi."
        )
        context.insert(entry)

        // `Format.typedNumber` écrit 70,2 et non 70.2 : les chiffres du poids
        // se lisent en français partout ailleurs dans l'application.
        #expect(JournalDayNutrition.weightLine(entry) == "70,2 kg")
    }

    @Test("un poids rond ne traîne pas de décimale")
    func aroundWeightHasNoTrailingZero() throws {
        let context = try makeContext()
        let entry = WeightEntry(dateKey: key("2026-08-12"), weightKg: 70)
        context.insert(entry)

        #expect(JournalDayNutrition.weightLine(entry) == "70 kg")
    }

    @Test("les repas parlants sortent dans l'ordre des repas, muets écartés")
    func spokenMealsAreSortedAndSilentOnesDropped() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déjeuner", sortOrder: 0, targetPct: 20)
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        let dinner = MealSlot(name: "Dîner", sortOrder: 2, targetPct: 41)
        context.insert(breakfast)
        context.insert(lunch)
        context.insert(dinner)

        // Volontairement dans le désordre : le tri doit venir de la fonction,
        // pas de l'ordre d'insertion.
        let dinnerNote = MealNote(dateKey: key("2026-08-12"), mealSlot: dinner, note: "Pâtes.")
        let blankNote = MealNote(dateKey: key("2026-08-12"), mealSlot: breakfast, note: "   ")
        let lunchNote = MealNote(dateKey: key("2026-08-12"), mealSlot: lunch, note: "Sushi.")
        context.insert(dinnerNote)
        context.insert(blankNote)
        context.insert(lunchNote)

        let spoken = JournalDayNutrition.spokenMeals(
            among: [dinnerNote, blankNote, lunchNote]
        )

        #expect(spoken == [lunchNote, dinnerNote])
    }

    @Test("une pesée sans commentaire, ou avec un commentaire blanc, n'est pas retenue")
    func silentWeighInsAreNotRetained() throws {
        let context = try makeContext()
        let noComment = WeightEntry(dateKey: key("2026-08-12"), weightKg: 70)
        let blankComment = WeightEntry(dateKey: key("2026-08-13"), weightKg: 70.2, note: "  \n ")
        context.insert(noComment)
        context.insert(blankComment)

        #expect(JournalDayNutrition.spokenWeight(among: [noComment, blankComment]) == nil)
    }

    @Test("une journée sans note de repas ni commentaire de pesée ne laisse rien à afficher")
    func asilentDayShowsNothing() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déjeuner", sortOrder: 0, targetPct: 20)
        context.insert(breakfast)
        let blankNote = MealNote(dateKey: key("2026-08-12"), mealSlot: breakfast, note: "")
        let weight = WeightEntry(dateKey: key("2026-08-12"), weightKg: 70)
        context.insert(blankNote)
        context.insert(weight)

        #expect(JournalDayNutrition.spokenMeals(among: [blankNote]).isEmpty)
        #expect(JournalDayNutrition.spokenWeight(among: [weight]) == nil)
    }
}
