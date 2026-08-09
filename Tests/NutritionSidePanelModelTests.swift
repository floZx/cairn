import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionSidePanelModel")
@MainActor
struct NutritionSidePanelModelTests {
    private func entry(_ raw: String, kcal: Double, protein: Double) -> FoodEntry {
        FoodEntry(
            dateKey: DateKey(raw: raw)!, mealSlot: nil, foodName: "x",
            kcal100: kcal, protein100: protein, carbs100: 0, fat100: 0,
            grams: 100, sortOrder: 0
        )
    }

    private func weight(_ raw: String, _ kg: Double) -> WeightEntry {
        WeightEntry(dateKey: DateKey(raw: raw)!, weightKg: kg)
    }

    @Test("les moyennes 7 j ne comptent que les jours enregistrés")
    func averagesIgnoreEmptyDays() throws {
        // Deux jours enregistrés dans la fenêtre : (2000+100) kcal et 1000 kcal.
        let entries = [
            entry("2026-08-08", kcal: 2000, protein: 100),
            entry("2026-08-08", kcal: 100, protein: 10),
            entry("2026-08-05", kcal: 1000, protein: 50),
            // Hors fenêtre de 7 jours (day-6 = 02/08).
            entry("2026-08-01", kcal: 9000, protein: 900),
        ]
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: [], goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.averageKcal7d == (2100 + 1000) / 2)
        #expect(model.averageProtein7d == (110 + 50) / 2)
    }

    @Test("régularité du mois et série")
    func monthRegularityAndStreak() throws {
        let entries = [
            entry("2026-08-06", kcal: 1, protein: 1),
            entry("2026-08-07", kcal: 1, protein: 1),
            entry("2026-08-08", kcal: 1, protein: 1),
            entry("2026-07-31", kcal: 1, protein: 1),  // mois précédent
        ]
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: [], goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.loggedThisMonth == 3)
        #expect(model.daysElapsedThisMonth == 8)
        #expect(model.streak == 3)
        #expect(model.loggedDays.contains("2026-07-31"))
    }

    @Test("la série s'arrête au premier trou")
    func streakStopsAtGap() throws {
        let entries = [
            entry("2026-08-08", kcal: 1, protein: 1),
            entry("2026-08-06", kcal: 1, protein: 1),  // trou le 07
        ]
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: [], goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.streak == 1)
    }

    @Test("le volet poids reprend les stats de WeightStats")
    func weightSection() throws {
        let weights = [
            weight("2026-07-25", 74.0), weight("2026-08-01", 73.5),
            weight("2026-08-08", 73.0),
        ]
        let model = NutritionSidePanelModel.compute(
            entries: [], weights: weights, goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.lastWeightKg == 73.0)
        #expect(model.weightDelta7d == -0.5)
        #expect(model.weightRatePerWeek != nil)
        #expect(model.weeksToGoal != nil)
        #expect(model.averageKcal7d == 0)
    }

    @Test("tout vide : zéros et nils, pas de crash")
    func emptyInputs() throws {
        let model = NutritionSidePanelModel.compute(
            entries: [], weights: [], goalKg: 0,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.averageKcal7d == 0)
        #expect(model.streak == 0)
        #expect(model.lastWeightKg == nil)
        #expect(model.weeksToGoal == nil)
    }
}
