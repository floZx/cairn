import Testing
import Foundation
@testable import Cairn

private struct TestPortion: FoodPortion {
    var kcal100: Double = 100
    var protein100: Double = 10
    var carbs100: Double = 20
    var fat100: Double = 5
    var grams: Double
}

@Suite("NutritionMath")
struct NutritionMathTests {
    @Test("les macros d'une portion suivent les grammes")
    func portionMacrosScaleByGrams() {
        let macros = Macros(of: TestPortion(grams: 250))
        #expect(macros == Macros(kcal: 250, protein: 25, carbs: 50, fat: 12.5))
    }

    @Test("addition et échelle")
    func addAndScale() {
        let sum = Macros(kcal: 100, protein: 10, carbs: 20, fat: 5)
            + Macros(kcal: 50, protein: 5, carbs: 10, fat: 2)
        #expect(sum == Macros(kcal: 150, protein: 15, carbs: 30, fat: 7))
        #expect(
            Macros(kcal: 100, protein: 10, carbs: 20, fat: 5).scaled(0.5)
                == Macros(kcal: 50, protein: 5, carbs: 10, fat: 2.5)
        )
    }

    @Test("la cible du jour déduit les glucides")
    func dailyTargetsDeriveCarbs() throws {
        // 2100 kcal, 145 P, 66 L -> glucides = (2100 - 580 - 594) / 4 = 231.5
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2100, proteinG: 145, fatG: 66)
        )
        #expect(daily.kcal == 2100)
        #expect(daily.protein == 145)
        #expect(daily.fat == 66)
        #expect(abs(daily.carbs - 231.5) < 0.001)
    }

    @Test("pas de cible kcal, pas de cible du jour")
    func dailyTargetsNilWithoutKcal() {
        #expect(NutritionMath.dailyTargets(kcalTarget: nil, proteinG: 145, fatG: 66) == nil)
    }

    @Test("les glucides déduits ne deviennent jamais négatifs")
    func carbsClampAtZero() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 500, proteinG: 145, fatG: 66)
        )
        #expect(daily.carbs == 0)
    }

    @Test("le budget restant borne chaque macro à zéro")
    func remainingDayClampsEachMacro() {
        let remaining = NutritionMath.remainingDay(
            daily: Macros(kcal: 2000, protein: 100, carbs: 250, fat: 60),
            consumed: Macros(kcal: 1800, protein: 120, carbs: 100, fat: 55)
        )
        #expect(remaining.kcal == 200)
        #expect(remaining.protein == 0)
        #expect(remaining.carbs == 150)
        #expect(remaining.fat == 5)
    }

    @Test("le dernier repas entamé affiche le reste réel du jour")
    func lastStartedMealShowsTrueRemaining() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2500, proteinG: 149, fatG: 66)
        )
        let meals: [NutritionMath.MealState] = [
            .init(pct: 28, started: true,
                  consumed: Macros(kcal: 365, protein: 25, carbs: 63, fat: 4)),
            .init(pct: 33, started: true,
                  consumed: Macros(kcal: 760, protein: 52, carbs: 89, fat: 22)),
            .init(pct: 0, started: true,
                  consumed: Macros(kcal: 742, protein: 5, carbs: 134, fat: 21)),
            .init(pct: 39, started: true,
                  consumed: Macros(kcal: 568, protein: 32, carbs: 56, fat: 20)),
        ]
        let targets = NutritionMath.adaptiveMealTargets(daily: daily, meals: meals)
        // Terminés -> part fixe du plan.
        #expect(targets[0] == NutritionMath.mealTarget(daily: daily, pct: 28))
        #expect(targets[1] == NutritionMath.mealTarget(daily: daily, pct: 33))
        // 0 % -> pas de cible.
        #expect(targets[2] == nil)
        // Dîner en cours : jour − (365+760+742) = 633, PAS 39 % de 2500.
        let dinner = try #require(targets[3])
        #expect(abs(dinner.kcal - 633) < 0.001)
        #expect(abs(dinner.carbs - (327.5 - 286)) < 0.001)
    }

    @Test("la cible du repas en cours ne saute pas quand on l'entame")
    func noFlipWhenCurrentMealStarts() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2500, proteinG: 149, fatG: 66)
        )
        let done: [NutritionMath.MealState] = [
            .init(pct: 28, started: true,
                  consumed: Macros(kcal: 365, protein: 25, carbs: 63, fat: 4)),
            .init(pct: 33, started: true,
                  consumed: Macros(kcal: 760, protein: 52, carbs: 89, fat: 22)),
            .init(pct: 0, started: true,
                  consumed: Macros(kcal: 742, protein: 5, carbs: 134, fat: 21)),
        ]
        let empty = NutritionMath.adaptiveMealTargets(
            daily: daily, meals: done + [.init(pct: 39, started: false, consumed: .zero)]
        )
        let started = NutritionMath.adaptiveMealTargets(
            daily: daily,
            meals: done + [.init(
                pct: 39, started: true,
                consumed: Macros(kcal: 568, protein: 32, carbs: 56, fat: 20)
            )]
        )
        let before = try #require(empty[3])
        let after = try #require(started[3])
        #expect(abs(before.kcal - after.kcal) < 0.001)
        #expect(abs(before.carbs - after.carbs) < 0.001)
    }

    @Test("un repas terminé grève le budget, les repas à venir se partagent le reste réel")
    func finishedMealReducesBudget() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2000, proteinG: 100, fatG: 60)
        )
        let meals: [NutritionMath.MealState] = [
            .init(pct: 20, started: true,
                  consumed: Macros(kcal: 400, protein: 20, carbs: 40, fat: 8)),
            .init(pct: 30, started: true,
                  consumed: Macros(kcal: 300, protein: 15, carbs: 30, fat: 6)),
            .init(pct: 25, started: false, consumed: .zero),
            .init(pct: 25, started: false, consumed: .zero),
        ]
        let targets = NutritionMath.adaptiveMealTargets(daily: daily, meals: meals)
        #expect(targets[0] == NutritionMath.mealTarget(daily: daily, pct: 20))
        // B en cours : part du budget en jeu (2000 − 400) × 30/80.
        #expect(abs(try #require(targets[1]).kcal - 1600 * 30 / 80) < 0.001)
        // C et D : reste réel (2000 − 400 − 300) réparti 25/50.
        #expect(abs(try #require(targets[2]).kcal - 1300 * 25 / 50) < 0.001)
        #expect(abs(try #require(targets[3]).kcal - 1300 * 25 / 50) < 0.001)
    }

    @Test("budget explosé : la cible en cours tombe à zéro, jamais négative")
    func blownBudgetClampsToZero() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2000, proteinG: 100, fatG: 60)
        )
        let meals: [NutritionMath.MealState] = [
            .init(pct: 50, started: true,
                  consumed: Macros(kcal: 2200, protein: 120, carbs: 300, fat: 70)),
            .init(pct: 50, started: true,
                  consumed: Macros(kcal: 100, protein: 5, carbs: 20, fat: 3)),
        ]
        let targets = NutritionMath.adaptiveMealTargets(daily: daily, meals: meals)
        let current = try #require(targets[1])
        #expect(current.kcal == 0)
        #expect(current.carbs == 0)
    }

    @Test("sans cible du jour, aucune cible de repas")
    func noDailyMeansAllNil() {
        let targets = NutritionMath.adaptiveMealTargets(
            daily: nil,
            meals: [
                .init(pct: 28, started: true,
                      consumed: Macros(kcal: 100, protein: 1, carbs: 1, fat: 1)),
                .init(pct: 39, started: false, consumed: .zero),
            ]
        )
        #expect(targets == [nil, nil])
    }

    @Test("le dépassement est gradué : rien, modéré jusqu'à +10 %, franc au-delà")
    func overshootIsGraduated() {
        // Dans la cible, ou à un demi-gramme près : rien à signaler.
        #expect(NutritionMath.overshoot(consumed: 90, target: 100) == nil)
        #expect(NutritionMath.overshoot(consumed: 100.4, target: 100) == nil)
        // Dépassement modéré : jusqu'à +10 % de la cible inclus.
        #expect(NutritionMath.overshoot(consumed: 101, target: 100) == .moderate)
        #expect(NutritionMath.overshoot(consumed: 110, target: 100) == .moderate)
        // Franc : au-delà de +10 %.
        #expect(NutritionMath.overshoot(consumed: 110.6, target: 100) == .heavy)
        #expect(NutritionMath.overshoot(consumed: 300, target: 100) == .heavy)
        // Pas de cible, pas de dépassement.
        #expect(NutritionMath.overshoot(consumed: 50, target: 0) == nil)
    }

    @Test("la couleur suit les entiers affichés, pas les décimales cachées")
    func overshootFollowsTheDisplayedFigures() {
        // « 33/33 » : dépassement réel de 0,6 g, invisible à l'écran.
        #expect(NutritionMath.overshoot(consumed: 33.4, target: 32.8) == nil)
        // Dès que les entiers diffèrent, la couleur revient.
        #expect(NutritionMath.overshoot(consumed: 33.6, target: 32.8) == .moderate)
        // Le seuil franc se lit lui aussi sur les entiers : 111 dépasse
        // 110 = 100 × 1,1, mais 110 affiché ne dépasse pas.
        #expect(NutritionMath.overshoot(consumed: 110.4, target: 100.4) == .moderate)
        #expect(NutritionMath.overshoot(consumed: 110.6, target: 100.4) == .heavy)
    }
}
