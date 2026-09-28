import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("TrainingLoad et Regularity")
@MainActor
struct TrainingLoadTests {
    /// Sunday 15 March 2026, noon UTC.
    private let reference = Date(timeIntervalSince1970: 1_773_576_000)
    private let calendar = ActivityStatistics.calendar
    private let floors: [Double] = [100, 120, 140, 160, 180]

    private func makeActivity(
        in context: ModelContext,
        id: Int64,
        daysBack: Int = 0,
        movingTime: Int = 3600,
        heartrate: Double? = nil,
        zoneSeconds: [Double]? = nil,
        sport: SportType = .run,
        distance: Double = 10_000
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Sortie \(id)", sportType: sport)
        activity.movingTime = movingTime
        activity.distance = distance
        activity.averageHeartrate = heartrate
        if let zoneSeconds {
            activity.hrZoneSeconds = zoneSeconds
            activity.hrZoneFloors = floors
        }
        let date = calendar.date(byAdding: .day, value: -daysBack, to: reference)!
        activity.startDate = date
        activity.startLocalDate = date
        context.insert(activity)
        return activity
    }

    // MARK: - Load

    @Test("la charge est la somme des minutes par zone pondérées par le numéro")
    func edwardsTrimp() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(
            in: context, id: 1, zoneSeconds: [600, 1200, 1800, 0, 60]
        )
        let load = TrainingLoad.load(of: activity, referenceFloors: nil)
        // 10×1 + 20×2 + 30×3 + 0×4 + 1×5
        #expect(load.value == 145)
        #expect(!load.estimated)
    }

    @Test("sans zones, la FC moyenne est placée dans les zones de référence")
    func estimatesFromAverageHeartrate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 1, movingTime: 3600, heartrate: 130)
        let load = TrainingLoad.load(of: activity, referenceFloors: floors)
        // 130 bpm is halfway through zone 2: weight 2.5, sixty minutes.
        #expect(load.value == 150)
        #expect(load.estimated)
    }

    @Test("le poids d'une FC suit les zones, continu, sans plafond au-delà de la 5")
    func zoneWeight() {
        #expect(TrainingLoad.zoneWeight(heartrate: 50, floors: floors) == 0.5)
        #expect(TrainingLoad.zoneWeight(heartrate: 100, floors: floors) == 1)
        #expect(TrainingLoad.zoneWeight(heartrate: 150, floors: floors) == 3.5)
        #expect(TrainingLoad.zoneWeight(heartrate: 200, floors: floors) == 5)
    }

    @Test("une sortie sans zones prend celles de la sortie la plus proche dans le temps")
    func nearestZones() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let withZones = makeActivity(in: context, id: 1, daysBack: 3, zoneSeconds: [3600, 0, 0, 0, 0])
        let without = makeActivity(in: context, id: 2, daysBack: 1, movingTime: 3600, heartrate: 130)
        let daily = TrainingLoad.daily([withZones, without])
        #expect(daily.count == 2)
        #expect(daily.estimatedCount == 1)
        let day = ActivityStatistics.day(of: without)!
        #expect(daily.load[day] == 150)
    }

    // MARK: - Fitness and fatigue

    @Test("forme et fatigue sont des moyennes exponentielles, la fraîcheur celle de la veille")
    func exponentialAverages() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 1, daysBack: 1, zoneSeconds: [0, 0, 0, 0, 0])
        activity.hrZoneSeconds = [4200, 0, 0, 0, 0]  // 70 minutes in zone 1: load 70
        let series = TrainingLoad.series(
            TrainingLoad.daily([activity]), calendar: calendar, now: reference
        )
        #expect(series.count == 2)
        let first = try #require(series.first)
        #expect(first.load == 70)
        #expect(abs(first.fitness - 70.0 / 42) < 1e-9)
        #expect(abs(first.fatigue - 10) < 1e-9)
        #expect(first.form == 0)
        let second = try #require(series.last)
        #expect(abs(second.form - (70.0 / 42 - 10)) < 1e-9)
        #expect(second.fatigue < first.fatigue)
    }

    @Test("l'état se lit relativement à la forme")
    func states() {
        func point(_ fitness: Double, _ form: Double) -> TrainingLoad.Point {
            TrainingLoad.Point(day: reference, load: 0, fitness: fitness, fatigue: 0, form: form)
        }
        #expect(TrainingLoad.state(of: point(50, -20)) == .overreaching)
        #expect(TrainingLoad.state(of: point(50, -10)) == .productive)
        #expect(TrainingLoad.state(of: point(50, 0)) == .neutral)
        #expect(TrainingLoad.state(of: point(50, 5)) == .fresh)
        #expect(TrainingLoad.state(of: point(50, 20)) == .detraining)
    }

    // MARK: - Regularity

    @Test("la série de semaines ne casse pas un lundi matin sans sortie")
    func streaks() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // `reference` is a Sunday: 7, 14 and 21 days back are the three
        // preceding Sundays; 35 back leaves a gap week before them.
        let activities = [7, 14, 21, 35, 42, 49, 56].map {
            makeActivity(in: context, id: Int64($0), daysBack: $0, heartrate: 130)
        }
        let regularity = Regularity.compute(
            activities,
            daily: TrainingLoad.daily(activities),
            periodStart: calendar.date(byAdding: .day, value: -27, to: reference)!,
            now: reference
        )
        #expect(regularity.currentStreak == 3)
        #expect(regularity.bestStreak == 4)
        #expect(regularity.activeDays == 3)
        #expect(regularity.periodDays == 28)
        #expect(abs(regularity.weeklyHours - 0.75) < 1e-9)
        // Fifty-two full weeks and this one, up to today (a Sunday: full too).
        #expect(regularity.days.count == 53 * 7)
    }

    @Test("la projection porte l'année entamée jusqu'au 31 décembre")
    func projection() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 1, daysBack: 0, movingTime: 7400, distance: 20_000)
        let regularity = Regularity.compute(
            [activity], daily: TrainingLoad.daily([activity]),
            periodStart: reference, now: reference
        )
        let projection = try #require(regularity.projection)
        // 15 March is day 74 of 365.
        #expect(projection.year == 2026)
        #expect(projection.projectedMovingTime == Int(7400.0 * 365 / 74))
        #expect(projection.mainSport == .run)
        #expect(abs(projection.projectedMainSportDistance - 20_000.0 * 365 / 74) < 1e-6)
    }

    // MARK: - Comparison totals

    @Test("la période précédente se compare à date, pas entière")
    func comparisonToDate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // Current year, 15 March: last year counts up to 15 March 2025 only.
        let before = makeActivity(in: context, id: 1, daysBack: 366)  // 14 March 2025
        let after = makeActivity(in: context, id: 2, daysBack: 360)   // 20 March 2025
        let now = makeActivity(in: context, id: 3, daysBack: 0)
        let stats = ActivityStatistics.compute(
            for: [before, after, now], period: .currentYear, now: reference
        )
        #expect(stats.count == 1)
        #expect(stats.comparison.count == 1)
        #expect(stats.comparison.movingTime == 3600)
    }
}
