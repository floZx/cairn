import Testing
import SwiftData
import Foundation
@testable import Cairn

private struct TestPortion: FoodPortion {
    var kcal100: Double = 100
    var protein100: Double = 10
    var carbs100: Double = 20
    var fat100: Double = 5
    var fiber100: Double?
    var grams: Double
}

@Suite("FiberTally")
struct FiberTallyTests {
    @Test("les fibres d'une portion suivent les grammes")
    func fiberScalesByGrams() {
        let tally = FiberTally(of: TestPortion(fiber100: 10, grams: 250))
        #expect(tally == FiberTally(grams: 25, unknownCount: 0))
    }

    @Test("un aliment sans fibres connues ne compte pas pour zéro")
    func unknownFiberIsCountedNotZeroed() {
        let tally = FiberTally(of: TestPortion(fiber100: nil, grams: 250))
        #expect(tally.grams == 0)
        // Le fait qui compte : la journée sait qu'elle ignore quelque chose.
        // Sans lui, « 0 g » serait indiscernable d'un aliment qui n'en a pas.
        #expect(tally.unknownCount == 1)
    }

    @Test("une journée additionne ce qu'elle sait et compte ce qu'elle ignore")
    func dayAddsKnownAndCountsUnknown() {
        let journee = [
            TestPortion(fiber100: 10, grams: 100),
            TestPortion(fiber100: nil, grams: 200),
            TestPortion(fiber100: 4, grams: 50),
            TestPortion(fiber100: nil, grams: 30),
        ]
        let total = journee.map { FiberTally(of: $0) }.reduce(.zero, +)
        #expect(total.grams == 12)
        #expect(total.unknownCount == 2)
    }

    @Test("l'arrondi est celui du gramme, et laisse le compte des muets")
    func roundingKeepsTheUnknownCount() {
        let tally = FiberTally(grams: 12.6, unknownCount: 3).rounded()
        #expect(tally == FiberTally(grams: 13, unknownCount: 3))
    }
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
        // Dans la cible : rien à signaler.
        #expect(NutritionMath.overshoot(consumed: 90, target: 100) == nil)
        #expect(NutritionMath.overshoot(consumed: 100.4, target: 100) == nil)
        // Et un peu au-dessus non plus : deux pour cent de tolérance, parce
        // qu'un gramme sur 149 n'est pas un dépassement mais le même repas
        // pesé deux fois.
        #expect(NutritionMath.overshoot(consumed: 102, target: 100) == nil)
        #expect(NutritionMath.overshoot(consumed: 150, target: 149) == nil)
        // Dépassement modéré : au-delà de la tolérance.
        #expect(NutritionMath.overshoot(consumed: 103, target: 100) == .moderate)
        #expect(NutritionMath.overshoot(consumed: 112, target: 100) == .moderate)
        // Franc : au-delà de +10 %, tolérance comprise.
        #expect(NutritionMath.overshoot(consumed: 113, target: 100) == .heavy)
        #expect(NutritionMath.overshoot(consumed: 300, target: 100) == .heavy)
        // Pas de cible, pas de dépassement.
        #expect(NutritionMath.overshoot(consumed: 50, target: 0) == nil)
    }

    @Test("un repas dans les neuf dixièmes de sa cible est dans le plan")
    func onTargetStartsAtNineTenths() {
        // Un repas se planifie, il ne se pèse pas au gramme : tomber à un
        // dixième près, c'est tomber juste.
        #expect(NutritionMath.isOnTarget(consumed: 90, target: 100))
        #expect(NutritionMath.isOnTarget(consumed: 100, target: 100))
        #expect(!NutritionMath.isOnTarget(consumed: 89, target: 100))
        // Un gramme passé la cible qu'on visait, c'est encore l'avoir
        // atteinte : les deux règles partagent la même tolérance, sinon
        // l'écran montrerait un chiffre ni dans la cible ni au-dessus.
        #expect(NutritionMath.isOnTarget(consumed: 101, target: 100))
        #expect(NutritionMath.isOnTarget(consumed: 150, target: 149))
        #expect(!NutritionMath.isOnTarget(consumed: 103, target: 100))
        // Sans cible, rien à atteindre.
        #expect(!NutritionMath.isOnTarget(consumed: 50, target: 0))
    }

    @Test("le vert se lit sur les entiers affichés, comme le dépassement")
    func onTargetFollowsTheDisplayedFigures() {
        // « 90/100 » à l'écran, même si 89,6 n'atteint pas les neuf dixièmes.
        #expect(NutritionMath.isOnTarget(consumed: 89.6, target: 100))
        // « 89/100 » reste en dessous.
        #expect(!NutritionMath.isOnTarget(consumed: 89.4, target: 100))
    }

    @Test("la couleur suit les entiers affichés, pas les décimales cachées")
    func overshootFollowsTheDisplayedFigures() {
        // « 33/33 » : dépassement réel de 0,6 g, invisible à l'écran.
        #expect(NutritionMath.overshoot(consumed: 33.4, target: 32.8) == nil)
        // Un gramme d'écart reste dans la tolérance d'une petite cible.
        #expect(NutritionMath.overshoot(consumed: 33.6, target: 32.8) == nil)
        // Les deux seuils se lisent sur les entiers, tolérance comprise.
        #expect(NutritionMath.overshoot(consumed: 112.4, target: 100.4) == .moderate)
        #expect(NutritionMath.overshoot(consumed: 113.6, target: 100.4) == .heavy)
    }
}

@Suite("Le champ décimal")
struct DecimalFieldTests {
    @Test("la virgule et le point mènent au même nombre")
    func bothSeparatorsParse() {
        // Le pavé numérique donne un point, le clavier français une virgule,
        // et un journal n'est pas l'endroit où apprendre la différence.
        #expect(DecimalField.parse("71,05") == 71.05)
        #expect(DecimalField.parse("71.05") == 71.05)
        #expect(DecimalField.parse(" 71,05 ") == 71.05)
        #expect(DecimalField.parse("71") == 71)
    }

    @Test("un champ vide ne vaut pas zéro")
    func anemptyFieldIsNotAValue() {
        // C'est ce qui permet d'effacer un champ et de retaper : sans ça, la
        // valeur retomberait à zéro et le champ se réécrirait sous les doigts.
        #expect(DecimalField.parse("") == nil)
        #expect(DecimalField.parse("   ") == nil)
        #expect(DecimalField.parse(",") == nil)
    }

    @Test("un séparateur fraîchement tapé ne fait pas revenir le champ en arrière")
    func aseparatorJustTypedSurvives() {
        // « 71, » vaut 71 pour Swift, et c'est ce qu'on veut : la valeur suit
        // la frappe, et comme le texte s'analyse déjà en cette valeur, la vue
        // ne le réécrit pas — la virgule reste à l'écran, les décimales
        // peuvent être tapées. C'est très exactement ce que
        // `TextField(value:format:)` ne fait pas.
        #expect(DecimalField.parse("71,") == 71)
        #expect(DecimalField.parse("71,") == DecimalField.parse("71"))
    }

    @Test("un nombre s'écrit comme on l'aurait tapé")
    func avalueIsWrittenTheWayItWouldBeTyped() {
        #expect(DecimalField.format(71) == "71")
        #expect(DecimalField.format(71.05) == "71,05")
        // Aucun « ,0 » sur un chiffre rond.
        #expect(DecimalField.format(70.0) == "70")
    }

    @Test("aller-retour : ce qui est écrit se relit à l'identique")
    func aroundTripKeepsTheValue() {
        for value in [70.0, 71.05, 0.5, 123.4] {
            #expect(DecimalField.parse(DecimalField.format(value)) == value)
        }
    }
}

@Suite("Ce que dit une cible de repas")
@MainActor
struct MealTargetKindTests {
    private func state(pct: Int, started: Bool) -> NutritionMath.MealState {
        NutritionMath.MealState(pct: pct, started: started, consumed: .zero)
    }

    @Test("un repas est terminé dès qu'un repas plus tard a commencé")
    func amealIsFinishedOnceALaterOneStarts() {
        let meals = [
            state(pct: 28, started: true),   // petit-déj
            state(pct: 33, started: true),   // déjeuner
            state(pct: 0, started: false),   // collation, sautée
            state(pct: 39, started: true),   // dîner, le dernier commencé
        ]
        // La collation est terminée elle aussi, bien que rien n'y ait été
        // mangé : ce qui termine un repas est qu'un repas plus tard ait
        // commencé, pas qu'on y ait touché.
        #expect(NutritionMath.superseded(in: meals) == [true, true, true, false])
    }

    @Test("une journée pas encore entamée n'a aucun repas terminé")
    func anuntouchedDayHasNoFinishedMeal() {
        let meals = [state(pct: 28, started: false), state(pct: 39, started: false)]
        #expect(NutritionMath.superseded(in: meals) == [false, false])
    }

    @Test("l'infobulle dit de quelle sorte est la cible")
    func thetooltipNamesTheKind() throws {
        // Un identifiant réel : `Meal` en porte un, et il n'y a pas de valeur
        // vide pour ce type.
        let context = ModelContext(try AppModelContainer.inMemory())
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 33)
        context.insert(slot)
        var meal = NutritionDayModel.Meal(
            slotID: slot.persistentModelID, slotName: "Déjeuner", rows: [],
            consumed: .zero, fiber: .zero,
            target: Macros(kcal: 792, protein: 49, carbs: 100, fat: 22),
            note: nil, targetKind: NutritionDayModel.TargetKind.planShare, pct: 33
        )
        #expect(NutritionDayView.targetExplanation(meal).contains("33 %"))
        #expect(NutritionDayView.targetExplanation(meal).contains("terminé"))

        meal.targetKind = NutritionDayModel.TargetKind.remaining
        #expect(NutritionDayView.targetExplanation(meal).contains("ce qu'il reste"))

        // Sans cible du tout — une collation à 0 % — le texte le dit aussi.
        meal.target = nil
        #expect(NutritionDayView.targetExplanation(meal).contains("pas de part"))
    }
}
