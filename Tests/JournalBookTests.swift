import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("La collecte du carnet")
@MainActor
struct JournalBookTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    /// Une sortie le 11 août 2026 à 10:00 heure de Paris.
    private func makeRun(
        in context: ModelContext, id: Int64, at epoch: TimeInterval = 1_786_435_200,
        distance: Double = 10_000, elevation: Double = 100, movingTime: Int = 3000
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: epoch)
        activity.distance = distance
        activity.totalElevationGain = elevation
        activity.movingTime = movingTime
        context.insert(activity)
        return activity
    }

    private func build(
        from: String = "2026-08-01", to: String = "2026-08-31",
        notes: [JournalNote] = [], activities: [Activity] = [],
        entries: [FoodEntry] = [], slots: [MealSlot] = [],
        mealNotes: [MealNote] = [], weights: [WeightEntry] = []
    ) -> JournalBook {
        JournalBook.build(
            from: key(from), to: key(to), notes: notes, activities: activities,
            entries: entries, slots: slots, mealNotes: mealNotes, weights: weights
        )
    }

    @Test("une journée muette n'entre pas dans le carnet")
    func asilentDayStaysOut() {
        #expect(build().days.isEmpty)
        #expect(build(notes: [JournalNote(date: key("2026-08-11"), text: "  ")]).days.isEmpty)
    }

    @Test("des aliments consignés sans un mot ne font pas une journée")
    func loggedFoodAloneIsNotAJournalDay() throws {
        // Consigner n'est pas écrire : la règle du journal vaut pour le carnet.
        // Le repas s'affichera si la journée existe pour une autre raison.
        let context = try makeContext()
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(slot)
        let entry = try NutritionJournal.addEntry(
            in: context, dateKey: key("2026-08-03"), slot: slot, foodName: "Riz",
            kcal100: 350, protein100: 8, carbs100: 78, fat100: 1, grams: 200
        )

        #expect(build(entries: [entry], slots: [slot]).days.isEmpty)

        let withWeight = build(
            entries: [entry], slots: [slot],
            weights: [WeightEntry(dateKey: key("2026-08-03"), weightKg: 70.2)]
        )
        #expect(withWeight.days.count == 1)
        #expect(withWeight.days[0].meals.count == 1)
    }

    @Test("chacune des quatre sources fait exister une journée")
    func everySourceMakesADay() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(slot)

        let written = build(notes: [JournalNote(date: key("2026-08-02"), text: "Repos.")])
        #expect(written.days.map(\.date.raw) == ["2026-08-02"])

        let ran = build(activities: [makeRun(in: context, id: 1)])
        #expect(ran.days.map(\.date.raw) == ["2026-08-11"])

        let ate = build(
            slots: [slot],
            mealNotes: [MealNote(dateKey: key("2026-08-03"), mealSlot: slot, note: "Sushi.")]
        )
        #expect(ate.days.map(\.date.raw) == ["2026-08-03"])

        let weighed = build(weights: [WeightEntry(dateKey: key("2026-08-04"), weightKg: 70.2)])
        #expect(weighed.days.map(\.date.raw) == ["2026-08-04"])
        #expect(weighed.days[0].weightKg == 70.2)
    }

    @Test("la période est une borne des deux côtés")
    func therangeIsInclusiveAndExclusive() throws {
        let context = try makeContext()
        let inside = makeRun(in: context, id: 1)
        let book = build(from: "2026-08-11", to: "2026-08-11", activities: [inside])
        #expect(book.days.count == 1)

        #expect(build(from: "2026-08-12", to: "2026-08-31", activities: [inside]).days.isEmpty)
        #expect(build(from: "2026-07-01", to: "2026-08-10", activities: [inside]).days.isEmpty)
    }

    @Test("les journées sortent de la plus ancienne à la plus récente")
    func daysComeOutOldestFirst() {
        // Un carnet se lit dans le sens du temps, à l'inverse de la liste du
        // journal, qui met la dernière note en haut.
        let book = build(notes: [
            JournalNote(date: key("2026-08-11"), text: "b"),
            JournalNote(date: key("2026-08-02"), text: "a"),
        ])
        #expect(book.days.map(\.date.raw) == ["2026-08-02", "2026-08-11"])
    }

    @Test("les tags d'une journée sont ceux de sa note")
    func adayCarriesItsTags() {
        let book = build(notes: [JournalNote(date: key("2026-08-02"), text: "Vu #Sam.")])
        #expect(book.days[0].tags.map(\.name) == ["Sam"])
    }

    @Test("les repas d'une journée portent leurs totaux et leur note")
    func mealsCarryTheirTotals() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(slot)
        let entry = try NutritionJournal.addEntry(
            in: context, dateKey: key("2026-08-03"), slot: slot, foodName: "Riz",
            kcal100: 350, protein100: 8, carbs100: 78, fat100: 1, grams: 200
        )
        let note = MealNote(dateKey: key("2026-08-03"), mealSlot: slot, note: "Bien.")
        context.insert(note)

        let book = build(entries: [entry], slots: [slot], mealNotes: [note])
        #expect(book.days.count == 1)
        #expect(book.days[0].meals.count == 1)
        #expect(book.days[0].meals[0].name == "Déjeuner")
        #expect(book.days[0].meals[0].kcal == 700)
        #expect(book.days[0].meals[0].note == "Bien.")
    }

    @Test("les totaux additionnent la période et la répartissent par sport")
    func totalsAddUpAndSplitBySport() throws {
        let context = try makeContext()
        let run = makeRun(in: context, id: 1)
        let other = makeRun(in: context, id: 2, at: 1_786_521_600, distance: 30_000)
        other.sportType = .ride

        let book = build(activities: [run, other])
        #expect(book.totals.activityCount == 2)
        #expect(book.totals.distance == 40_000)
        #expect(book.totals.elevation == 200)
        #expect(book.totals.movingTime == 6000)
        // Le sport le plus parcouru d'abord : c'est ce qui a pesé sur la période.
        #expect(book.totals.bySport.map(\.sport) == [.ride, .run])
        #expect(book.totals.bySport[0].count == 1)
    }

    @Test("les poids de début et de fin encadrent la période")
    func weightsBookendTheRange() {
        let book = build(weights: [
            WeightEntry(dateKey: key("2026-08-20"), weightKg: 69.8),
            WeightEntry(dateKey: key("2026-08-02"), weightKg: 70.6),
        ])
        #expect(book.totals.firstWeightKg == 70.6)
        #expect(book.totals.lastWeightKg == 69.8)
    }
}
