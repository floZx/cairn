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

    @Test("les marques d'une journée disent ses sports et sa pesée")
    func marksCarrySportsAndWeighIn() throws {
        let context = try makeContext()
        let run = Activity(stravaID: 1, name: "Footing", sportType: .run)
        run.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        let secondRun = Activity(stravaID: 2, name: "Footing du soir", sportType: .run)
        secondRun.startDate = Date(timeIntervalSince1970: 1_786_471_200)
        let ride = Activity(stravaID: 3, name: "Vélo", sportType: .ride)
        ride.startDate = Date(timeIntervalSince1970: 1_786_478_400)
        [run, secondRun, ride].forEach(context.insert)
        let weight = WeightEntry(dateKey: key("2026-08-11"), weightKg: 70.2)
        context.insert(weight)

        let marks = JournalDaySources.marks(
            activities: [ride, run, secondRun], weights: [weight]
        )
        let day = marks[key("2026-08-11")]
        // Deux courses et un vélo font deux glyphes, dans l'ordre où la
        // journée s'est déroulée.
        #expect(day?.sports == [.run, .ride])
        #expect(day?.weighed == true)
        // Aucune photo sur ces sorties : la journée n'en annonce pas.
        #expect(day?.photoIDs.isEmpty == true)
    }

    @Test("les photos d'une sortie entrent dans les marques de sa journée")
    func outingPhotosMarkTheirDay() throws {
        let context = try makeContext()
        let run = Activity(stravaID: 1, name: "Trail", sportType: .trailRun)
        run.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        context.insert(run)
        for index in 0..<2 {
            let photo = ActivityPhoto(uniqueID: "p\(index)")
            photo.sortIndex = index
            photo.activity = run
            photo.activityUUID = run.uuid
            context.insert(photo)
        }
        try context.save()

        let marks = JournalDaySources.marks(activities: [run], weights: [])
        // Une photo portée par une sortie compte comme une photo de la
        // journée : les deux disent à quoi elle a ressemblé.
        #expect(marks[key("2026-08-11")]?.photoIDs.count == 2)
    }

    @Test("une journée sans rien à marquer n'entre pas dans la table")
    func aplainDayCarriesNoMarks() {
        #expect(JournalDaySources.marks(activities: [], weights: []).isEmpty)
    }

    @Test("une sortie muette compte quand même comme une sortie")
    func asilentOutingStillMarksItsDay() throws {
        let context = try makeContext()
        // Rien d'écrit dessus : elle n'entre pas dans les textes du jour, mais
        // le glyphe est la seule chose de la rangée qui dira qu'elle a eu lieu.
        let run = Activity(stravaID: 1, name: "Footing", sportType: .run)
        run.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        context.insert(run)

        #expect(
            JournalDaySources.elsewhereNotes(
                activities: [run], mealNotes: [], weights: []
            ).isEmpty
        )
        #expect(
            JournalDaySources.marks(activities: [run], weights: [])[
                key("2026-08-11")
            ]?.sports == [.run]
        )
    }
}
