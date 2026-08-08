// Tests/WeightStatsTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("WeightStats")
struct WeightStatsTests {
    private func point(_ raw: String, _ kg: Double) -> WeightPoint {
        WeightPoint(dateKey: DateKey(raw: raw)!, weightKg: kg)
    }

    @Test("le delta 7 jours compare les bornes de la fenêtre")
    func deltaSevenDays() {
        let weights = [
            point("2026-06-20", 74.0), point("2026-06-24", 73.5),
            point("2026-06-30", 73.0),
        ]
        // Fenêtre 7 j finissant au 30 -> >= 23/06 : 73.5 (24) -> 73.0 (30).
        #expect(WeightStats.delta(weights, days: 7) == -0.5)
        #expect(WeightStats.delta([point("2026-06-30", 73.0)], days: 7) == nil)
    }

    @Test("le rythme hebdomadaire sort de la régression")
    func ratePerWeekFromTwoPoints() throws {
        let weights = [point("2026-06-16", 74.0), point("2026-06-30", 73.0)]
        // -1.0 kg en 14 jours = -0.5 kg/semaine.
        let rate = try #require(WeightStats.ratePerWeek(weights, days: 30))
        #expect(abs(rate - -0.5) < 0.0001)
    }

    @Test("la régression voit la tendance qu'un calcul fin-début raterait")
    func rateUsesRegressionNotEndpoints() throws {
        // Rebond final isolé : fin-début donnerait 0, la régression descend.
        let weights = [
            point("2026-06-01", 74.0), point("2026-06-02", 73.5),
            point("2026-06-03", 73.0), point("2026-06-04", 74.0),
        ]
        let rate = try #require(WeightStats.ratePerWeek(weights, days: 30))
        #expect(abs((rate * 100).rounded() / 100 - -0.35) < 0.0001)
    }

    @Test("l'estimation vers l'objectif suit le rythme, ou s'abstient")
    func weeksToGoal() throws {
        let losing = [point("2026-06-16", 74.0), point("2026-06-30", 73.0)]
        // Reste 3 kg à -0.5 kg/sem -> 6 semaines. Tolérance plutôt qu'égalité
        // exacte : le rythme sort d'une régression en flottants.
        let weeks = try #require(WeightStats.weeksToGoal(losing, goal: 70, days: 30))
        #expect(abs(weeks - 6.0) < 0.0001)
        // Prendre du poids alors qu'il faut en perdre -> pas d'estimation.
        let gaining = [point("2026-06-16", 72.0), point("2026-06-30", 73.0)]
        #expect(WeightStats.weeksToGoal(gaining, goal: 70, days: 30) == nil)
        #expect(WeightStats.weeksToGoal([], goal: 70, days: 30) == nil)
    }

    @Test("la fenêtre est relative à la dernière pesée, pas à aujourd'hui")
    func windowRelativeToLastWeighIn() {
        let weights = [
            point("2026-05-01", 76.0), point("2026-06-20", 74.0),
            point("2026-06-28", 73.6), point("2026-07-01", 73.4),
        ]
        let got = WeightStats.window(weights, days: 30).map(\.dateKey.raw)
        #expect(got == ["2026-06-20", "2026-06-28", "2026-07-01"])
    }

    @Test("fenêtre nil = tout, liste vide = vide")
    func windowNilAndEmpty() {
        let weights = [point("2026-05-01", 76.0), point("2026-07-01", 73.4)]
        #expect(WeightStats.window(weights, days: nil) == weights)
        #expect(WeightStats.window([], days: 30).isEmpty)
    }

    @Test("la série de jours consignés compte en remontant")
    func streakCountsBackwards() {
        let logged: Set<String> = ["2026-06-28", "2026-06-29", "2026-06-30"]
        #expect(WeightStats.loggingStreak(
            loggedDates: logged, endingAt: DateKey(raw: "2026-06-30")!
        ) == 3)
        #expect(WeightStats.loggingStreak(
            loggedDates: logged, endingAt: DateKey(raw: "2026-06-27")!
        ) == 0)
        #expect(WeightStats.loggingStreak(
            loggedDates: ["2026-06-30"], endingAt: DateKey(raw: "2026-06-30")!
        ) == 1)
    }
}
