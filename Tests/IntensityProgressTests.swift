import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Intensity et SportProgress")
@MainActor
struct IntensityProgressTests {
    /// Sunday 15 March 2026, noon UTC.
    private let reference = Date(timeIntervalSince1970: 1_773_576_000)
    private let calendar = ActivityStatistics.calendar

    private func makeActivity(
        in context: ModelContext,
        id: Int64,
        daysBack: Int = 0,
        sport: SportType = .run,
        distance: Double = 10_000,
        movingTime: Int = 3000,
        elevation: Double = 0,
        heartrate: Double? = 150,
        zoneSeconds: [Double]? = nil
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Sortie \(id)", sportType: sport)
        activity.distance = distance
        activity.movingTime = movingTime
        activity.averageSpeed = distance / Double(movingTime)
        activity.totalElevationGain = elevation
        activity.averageHeartrate = heartrate
        activity.hrZoneSeconds = zoneSeconds
        let date = calendar.date(byAdding: .day, value: -daysBack, to: reference)!
        activity.startDate = date
        activity.startLocalDate = date
        context.insert(activity)
        return activity
    }

    private func weekStart(daysBack: Int) -> Date {
        let date = calendar.date(byAdding: .day, value: -daysBack, to: reference)!
        return calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    // MARK: - Intensity

    @Test("les zones s'additionnent par période et par créneau ; les sorties sans zones sont comptées à part")
    func splitsByZone() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, daysBack: 0, zoneSeconds: [600, 1800, 600, 0, 0]),
            makeActivity(in: context, id: 2, daysBack: 7, zoneSeconds: [0, 1200, 0, 600, 600]),
            makeActivity(in: context, id: 3, daysBack: 7),
            // Before the first slot: ignored.
            makeActivity(in: context, id: 4, daysBack: 30, zoneSeconds: [9999, 0, 0, 0, 0]),
        ]
        let slots = [weekStart(daysBack: 7), weekStart(daysBack: 0)]
        let intensity = Intensity.compute(activities, slotStarts: slots, unit: .weekOfYear)
        #expect(intensity.seconds == [600, 3000, 600, 600, 600])
        #expect(intensity.covered == 2)
        #expect(intensity.count == 3)
        #expect(intensity.slots.map(\.seconds) == [[0, 1200, 0, 600, 600], [600, 1800, 600, 0, 0]])
        #expect(abs(intensity.easy - 3600.0 / 5400) < 1e-9)
        #expect(intensity.profile == .polarized)
    }

    @Test("le profil suit les parts de zone 3 et de zones 4–5")
    func profiles() {
        func profile(_ seconds: [Double]) -> Intensity.Profile? {
            Intensity(seconds: seconds, slots: [], covered: 1, count: 1).profile
        }
        #expect(profile([0, 50, 30, 10, 10]) == .threshold)
        #expect(profile([0, 97, 2, 1, 0]) == .easyOnly)
        #expect(profile([0, 75, 15, 10, 0]) == .pyramidal)
        #expect(profile([0, 80, 5, 10, 5]) == .polarized)
        #expect(profile([0, 0, 0, 0, 0]) == nil)
    }

    // MARK: - Progress

    @Test("le trail compte ses km-effort, la route ses km")
    func effortDistance() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let trail = makeActivity(in: context, id: 1, sport: .trailRun, elevation: 500)
        let road = makeActivity(in: context, id: 2, sport: .run, elevation: 500)
        #expect(SportProgress.effortDistance(of: trail) == 15_000)
        #expect(SportProgress.effortDistance(of: road) == 10_000)
    }

    @Test("la tendance est la droite des moindres carrés, l'efficacité des mètres par battement")
    func trendAndEfficiency() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // Faster by 100 s each week, same heart rate.
        let activities = [3200, 3100, 3000].enumerated().map { index, time in
            makeActivity(in: context, id: Int64(index), daysBack: 14 - index * 7, movingTime: time)
        }
        let progress = SportProgress.compute(
            activities, sport: .run,
            since: calendar.date(byAdding: .day, value: -30, to: reference)!
        )
        #expect(progress.points.count == 3)
        let speed = try #require(progress.trend(.speed))
        #expect(abs(speed.start.value - 10_000.0 / 3200) < 0.01)
        #expect(abs(speed.end.value - 10_000.0 / 3000) < 0.01)
        #expect(speed.change > 6)
        let efficiency = try #require(progress.points.last?.efficiency)
        #expect(abs(efficiency - 10_000.0 / 3000 * 60 / 150) < 1e-9)
        #expect(progress.trend(.heartrate).map { abs($0.change) < 1e-9 } == true)
    }

    @Test("les records du sport : le plus rapide parmi les sorties d'au moins la moitié de la médiane")
    func sportRecords() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, daysBack: 1, distance: 2_000, movingTime: 400),
            makeActivity(in: context, id: 2, daysBack: 2, distance: 10_000, movingTime: 2700),
            makeActivity(in: context, id: 3, daysBack: 3, distance: 12_000, movingTime: 3600, elevation: 300),
            makeActivity(in: context, id: 4, daysBack: 4, sport: .ride, distance: 60_000, movingTime: 7200),
        ]
        let progress = SportProgress.compute(activities, sport: .run, since: reference)
        let byKind = Dictionary(uniqueKeysWithValues: progress.records.map { ($0.kind, $0.activityName) })
        #expect(byKind[.distance] == "Sortie 3")
        #expect(byKind[.elevation] == "Sortie 3")
        #expect(byKind[.speed] == "Sortie 2")
    }

    @Test("un sport n'a de progression qu'à partir de trois sorties sur la période")
    func sportsWorthAProgression() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = (0..<3).map { makeActivity(in: context, id: Int64($0), daysBack: $0) }
            + (3..<5).map { makeActivity(in: context, id: Int64($0), daysBack: $0, sport: .ride) }
        let since = calendar.date(byAdding: .day, value: -10, to: reference)!
        #expect(SportProgress.sports(in: activities, since: since) == [.run])
    }
}

@Suite("SportProgress — matériel")
@MainActor
struct SportProgressGearTests {
    @Test("les km d'un matériel se recalculent sur toutes les sorties, pas ceux de Strava")
    func gearDistanceIsRecomputed() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let shoes = Gear(stravaID: "g1", name: "Peregrine")
        shoes.totalDistance = 1_000  // Strava's figure, stale.
        context.insert(shoes)
        let now = Date()
        for (index, sport) in [SportType.run, .trailRun, .run].enumerated() {
            let activity = Activity(stravaID: Int64(index), name: "S\(index)", sportType: sport)
            activity.distance = 10_000
            activity.movingTime = 3000
            activity.gearID = "g1"
            activity.gear = shoes
            activity.startDate = now
            activity.startLocalDate = now
            context.insert(activity)
        }
        try context.save()
        let distances = SportProgress.gearDistances(in: context)
        #expect(distances["g1"] == 30_000)

        let runs = try context.fetch(FetchDescriptor<Activity>()).filter { $0.sportType == .run }
        let progress = SportProgress.compute(
            runs, sport: .run, since: now.addingTimeInterval(-86_400), gearDistances: distances
        )
        #expect(progress.gear.first?.totalDistance == 30_000)
        #expect(progress.gear.first?.count == 2)
    }
}
