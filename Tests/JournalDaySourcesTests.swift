import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Les sources d'un jour de journal")
@MainActor
struct JournalDaySourcesTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    /// Un contexte en mémoire : `MealNote` référence un `MealSlot`, et une
    /// relation SwiftData veut un store, même jetable.
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("un jour rassemble ses sorties, ses repas et sa pesée dans l'ordre")
    func groupsEverythingWrittenThatDay() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 3, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)

        let activity = Activity(stravaID: 1, name: "Footing", sportType: .run)
        // 2026-08-11 à 08:00 UTC : le jour se lit dans le calendrier local,
        // et une heure du matin ne bascule pas de jour en France.
        activity.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        activity.activityDescription = "Jambes lourdes."
        context.insert(activity)

        let lateMeal = MealNote(
            dateKey: key("2026-08-11"), mealSlot: dinner, note: "Sushi."
        )
        let earlyMeal = MealNote(
            dateKey: key("2026-08-11"), mealSlot: breakfast, note: "Skyr."
        )
        context.insert(lateMeal)
        context.insert(earlyMeal)
        let weight = WeightEntry(
            dateKey: key("2026-08-11"), weightKg: 70.2, note: "Bien dormi."
        )
        context.insert(weight)

        let byDay = JournalDaySources.elsewhereNotes(
            activities: [activity], mealNotes: [lateMeal, earlyMeal],
            weights: [weight]
        )

        // Les sorties, puis les repas dans l'ordre de la journée, la pesée en
        // dernier — c'est cet ordre qui décide de la ligne résumant le jour.
        #expect(
            byDay[key("2026-08-11")]
                == ["Jambes lourdes.", "Skyr.", "Sushi.", "Bien dormi."]
        )
    }

    @Test("une pesée muette n'écrit rien")
    func asilentWeighInSaysNothing() throws {
        let context = try makeContext()
        let weight = WeightEntry(dateKey: key("2026-08-10"), weightKg: 70.2)
        context.insert(weight)
        let blank = WeightEntry(
            dateKey: key("2026-08-09"), weightKg: 70.4, note: "  \n "
        )
        context.insert(blank)

        let byDay = JournalDaySources.elsewhereNotes(
            activities: [], mealNotes: [], weights: [weight, blank]
        )
        #expect(byDay.isEmpty)
    }

    @Test("une note de repas suffit à faire exister un jour")
    func amealNoteAloneMakesADay() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let note = MealNote(
            dateKey: key("2026-08-08"), mealSlot: lunch, note: "Amie #Sushi."
        )
        context.insert(note)

        let days = JournalDay.merge(
            notes: [],
            elsewhereNotes: JournalDaySources.elsewhereNotes(
                activities: [], mealNotes: [note], weights: []
            )
        )
        #expect(days.map(\.date.raw) == ["2026-08-08"])
        #expect(days[0].summary == "Amie #Sushi.")
        // Le tag compte comme celui d'une sortie : c'est la même personne qui
        // l'a écrit, et la barre latérale doit le lister.
        #expect(days[0].tags.contains(JournalTag(name: "Sushi")!))
    }

    @Test("la recherche trouve un jour par le texte d'un repas, et le cite")
    func searchReachesAMealNote() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let meal = MealNote(
            dateKey: key("2026-08-08"), mealSlot: lunch,
            note: "Amie Sushi, pétage de bide."
        )
        context.insert(meal)
        let activity = Activity(stravaID: 2, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: 1_786_176_000)
        activity.activityDescription = "Jambes lourdes."
        context.insert(activity)

        let days = JournalDay.merge(
            notes: [],
            elsewhereNotes: JournalDaySources.elsewhereNotes(
                activities: [activity], mealNotes: [meal], weights: []
            )
        )
        #expect(days.count == 1)
        // La sortie a écrit la première : c'est elle qui donne la ligne.
        #expect(days[0].summary == "Jambes lourdes.")
        #expect(days[0].matches(query: "sushi"))
        #expect(days[0].excerpt(matching: "sushi")?.contains("pétage") == true)
    }

    @Test("un repas sans note ne raconte rien")
    func anuntoldMealStaysOut() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let empty = MealNote(dateKey: key("2026-08-08"), mealSlot: lunch, note: "")
        context.insert(empty)

        #expect(
            JournalDaySources.elsewhereNotes(
                activities: [], mealNotes: [empty], weights: []
            ).isEmpty
        )
    }
}
