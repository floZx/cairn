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
}
