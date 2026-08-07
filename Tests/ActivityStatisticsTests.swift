import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("ActivityStatistics")
@MainActor
struct ActivityStatisticsTests {
    /// 15 March 2026, so every expected month is a fixed offset from it.
    private let reference = Date(timeIntervalSince1970: 1_773_600_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func makeActivity(
        in context: ModelContext,
        id: Int64,
        sport: SportType = .ride,
        distance: Double = 10_000,
        movingTime: Int = 3600,
        elevation: Double = 200,
        monthsBack: Int = 0,
        name: String = "Sortie"
    ) -> Activity {
        let activity = Activity(stravaID: id, name: name, sportType: sport)
        activity.distance = distance
        activity.movingTime = movingTime
        activity.totalElevationGain = elevation
        let date = calendar.date(byAdding: .month, value: -monthsBack, to: reference)!
        activity.startDate = date
        activity.startLocalDate = date
        context.insert(activity)
        return activity
    }

    @Test("sans activité, tout est à zéro et rien n'est inventé")
    func handlesAnEmptySet() {
        let stats = ActivityStatistics.compute(for: [])

        #expect(stats == .empty)
        #expect(stats.records.isEmpty)
        #expect(stats.months.isEmpty)
    }

    @Test("les cumuls portent sur le temps, le dénivelé et le nombre")
    func sumsWhatAddsUp() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, movingTime: 3600, elevation: 200),
            makeActivity(in: context, id: 2, movingTime: 1800, elevation: 350),
        ]

        let stats = ActivityStatistics.compute(for: activities)

        #expect(stats.count == 2)
        #expect(stats.movingTime == 5400)
        #expect(stats.elevationGain == 550)
    }

    @Test("la distance est ventilée par sport, jamais additionnée entre sports")
    func keepsDistancePerSport() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, sport: .ride, distance: 80_000, movingTime: 10_000),
            makeActivity(in: context, id: 2, sport: .ride, distance: 20_000, movingTime: 3_000),
            makeActivity(in: context, id: 3, sport: .swim, distance: 2_000, movingTime: 2_000),
        ]

        let stats = ActivityStatistics.compute(for: activities)

        #expect(stats.sports.count == 2)
        // Ordered by time, the one measure that compares across sports.
        #expect(stats.sports.map(\.sport) == [.ride, .swim])
        let ride = stats.sports.first { $0.sport == .ride }
        #expect(ride?.count == 2)
        #expect(ride?.distance == 100_000)
        #expect(ride?.movingTime == 13_000)
        #expect(stats.sports.first { $0.sport == .swim }?.distance == 2_000)
    }

    @Test("l'ordre par sport est stable quand les temps sont égaux")
    func breaksTiesByName() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, sport: .swim, movingTime: 3600),
            makeActivity(in: context, id: 2, sport: .ride, movingTime: 3600),
        ]

        // "Natation" before "Vélo": without the tie-break the order would follow
        // the dictionary's, and change between runs.
        let first = ActivityStatistics.compute(for: activities).sports.map(\.sport)
        let second = ActivityStatistics.compute(for: activities.reversed()).sports.map(\.sport)
        #expect(first == second)
    }

    @Test("chaque record désigne l'activité qui le détient")
    func findsRecordHolders() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(
                in: context, id: 1, distance: 42_000, movingTime: 20_000,
                elevation: 300, name: "La plus longue"
            ),
            makeActivity(
                in: context, id: 2, distance: 10_000, movingTime: 3_600,
                elevation: 1_800, name: "La plus grimpante"
            ),
        ]

        let stats = ActivityStatistics.compute(for: activities)
        let byKind = Dictionary(uniqueKeysWithValues: stats.records.map { ($0.kind, $0) })

        #expect(byKind[.distance]?.activityName == "La plus longue")
        #expect(byKind[.distance]?.formattedValue.contains("42") == true)
        #expect(byKind[.elevation]?.activityName == "La plus grimpante")
        #expect(byKind[.elevation]?.formattedValue == "1800 m")
        #expect(byKind[.duration]?.activityName == "La plus longue")
    }

    @Test("un record nul n'est pas affiché")
    func skipsEmptyRecords() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // A gym session: time, but no distance and no climbing.
        let indoors = makeActivity(
            in: context, id: 1, sport: .workout, distance: 0, elevation: 0
        )

        let stats = ActivityStatistics.compute(for: [indoors])

        #expect(stats.records.map(\.kind) == [.duration])
    }

    @Test("les douze mois sont contigus, mois vides compris")
    func buildsTwelveContiguousMonths() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, distance: 30_000, monthsBack: 0),
            // A gap of ten months in between, which has to show as zeros rather
            // than putting the two bars side by side.
            makeActivity(in: context, id: 2, distance: 10_000, monthsBack: 11),
        ]

        let months = ActivityStatistics.compute(for: activities).months

        #expect(months.count == 12)
        #expect(months.map(\.month) == months.map(\.month).sorted())
        #expect(months.first?.distance == 10_000)
        #expect(months.last?.distance == 30_000)
        #expect(months.dropFirst().dropLast().allSatisfy { $0.distance == 0 })
    }

    @Test("la fenêtre se termine sur le mois de l'activité la plus récente")
    func endsOnTheMostRecentMonth() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // Nothing recent: the window follows the data, not today's date, so a
        // filter on an old season still charts that season.
        let old = makeActivity(in: context, id: 1, monthsBack: 30)

        let months = ActivityStatistics.compute(for: [old]).months

        let expected = calendar.date(
            from: calendar.dateComponents(
                [.year, .month],
                from: calendar.date(byAdding: .month, value: -30, to: reference)!
            )
        )
        #expect(months.last?.month == expected)
        #expect(months.last?.distance == 10_000)
    }
}
