import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("ActivityStatistics")
@MainActor
struct ActivityStatisticsTests {
    /// Sunday 15 March 2026. A Sunday on purpose: with Monday-first weeks it is
    /// the *last* day of its week, which is where an off-by-one would show.
    private let reference = Date(timeIntervalSince1970: 1_773_600_000)

    /// Monday-first, matching the production calendar. A Sunday-first calendar
    /// here would compute different expectations and hide a real disagreement.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    private func makeActivity(
        in context: ModelContext,
        id: Int64,
        sport: SportType = .ride,
        distance: Double = 10_000,
        movingTime: Int = 3600,
        elevation: Double = 200,
        monthsBack: Int = 0,
        daysBack: Int = 0,
        name: String = "Sortie"
    ) -> Activity {
        let activity = Activity(stravaID: id, name: name, sportType: sport)
        activity.distance = distance
        activity.movingTime = movingTime
        activity.totalElevationGain = elevation
        let shifted = calendar.date(byAdding: .month, value: -monthsBack, to: reference)!
        let date = calendar.date(byAdding: .day, value: -daysBack, to: shifted)!
        activity.startDate = date
        activity.startLocalDate = date
        context.insert(activity)
        return activity
    }

    private func stats(
        _ activities: [Activity], _ period: StatsPeriod = .twelveMonths
    ) -> ActivityStatistics {
        ActivityStatistics.compute(for: activities, period: period, now: reference)
    }

    private func startOfWeek(daysBack: Int = 0) -> Date? {
        let date = calendar.date(byAdding: .day, value: -daysBack, to: reference)!
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    // MARK: - Totals

    @Test("sans activité, tout est à zéro et rien n'est inventé")
    func handlesAnEmptySet() {
        let result = stats([])

        #expect(result.count == 0)
        #expect(result.movingTime == 0)
        #expect(result.elevationGain == 0)
        #expect(result.sports.isEmpty)
        #expect(result.records.isEmpty)
        // The slots are still laid out: a period is a stated range, so an empty
        // one is twelve empty bars rather than nothing at all.
        #expect(result.slots.count == 12)
        #expect(result.slots.allSatisfy { $0.distance == 0 && $0.comparisonDistance == 0 })
    }

    @Test("les cumuls portent sur le temps, le dénivelé et le nombre")
    func sumsWhatAddsUp() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, movingTime: 3600, elevation: 200),
            makeActivity(in: context, id: 2, movingTime: 1800, elevation: 350),
        ]

        let result = stats(activities)

        #expect(result.count == 2)
        #expect(result.movingTime == 5400)
        #expect(result.elevationGain == 550)
    }

    @Test("la distance est ventilée par sport, jamais additionnée entre sports")
    func keepsDistancePerSport() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, sport: .ride, distance: 80_000, movingTime: 10_000),
            makeActivity(in: context, id: 2, sport: .ride, distance: 20_000, movingTime: 3_000),
            makeActivity(in: context, id: 3, sport: .swim, distance: 2_000, movingTime: 2_000),
        ]

        let result = stats(activities)

        #expect(result.sports.count == 2)
        // Ordered by time, the one measure that compares across sports.
        #expect(result.sports.map(\.sport) == [.ride, .swim])
        let ride = result.sports.first { $0.sport == .ride }
        #expect(ride?.count == 2)
        #expect(ride?.distance == 100_000)
        #expect(ride?.movingTime == 13_000)
        #expect(result.sports.first { $0.sport == .swim }?.distance == 2_000)
    }

    @Test("l'ordre par sport est stable quand les temps sont égaux")
    func breaksTiesByName() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, sport: .swim, movingTime: 3600),
            makeActivity(in: context, id: 2, sport: .ride, movingTime: 3600),
        ]

        // Without the tie-break the order would follow the dictionary's, and
        // change between runs.
        #expect(stats(activities).sports.map(\.sport)
            == stats(activities.reversed()).sports.map(\.sport))
    }

    // MARK: - Records

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

        let byKind = Dictionary(
            uniqueKeysWithValues: stats(activities).records.map { ($0.kind, $0) }
        )

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

        #expect(stats([indoors]).records.map(\.kind) == [.duration])
    }

    // MARK: - Granularity

    @Test("les fenêtres courtes se comptent en semaines, les longues en mois")
    func choosesGranularityFromThePeriod() {
        #expect(StatsPeriod.threeMonths.granularity == .week)
        #expect(StatsPeriod.sixMonths.granularity == .week)
        #expect(StatsPeriod.twelveMonths.granularity == .month)
        #expect(StatsPeriod.currentYear.granularity == .month)
    }

    @Test("chaque période a le bon nombre de créneaux")
    func sizesTheWindowPerPeriod() {
        // Weeks for the short windows: three bars is not a chart.
        #expect(StatsPeriod.threeMonths.slotCount(now: reference, calendar: calendar) == 13)
        #expect(StatsPeriod.sixMonths.slotCount(now: reference, calendar: calendar) == 26)
        #expect(StatsPeriod.twelveMonths.slotCount(now: reference, calendar: calendar) == 12)
        // March, so the calendar year runs January through March.
        #expect(StatsPeriod.currentYear.slotCount(now: reference, calendar: calendar) == 3)
    }

    @Test("les semaines commencent le lundi, dimanche compris")
    func bucketsWeeksFromMonday() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            // The reference Sunday, and the Wednesday before it: same week.
            makeActivity(in: context, id: 1, distance: 12_000, daysBack: 0),
            makeActivity(in: context, id: 2, distance: 8_000, daysBack: 4),
            // The Sunday before that closes the *previous* week, which a
            // Sunday-first calendar would have opened instead.
            makeActivity(in: context, id: 3, distance: 5_000, daysBack: 7),
        ]

        let result = stats(activities, .threeMonths)

        #expect(result.slots.count == 13)
        #expect(result.slots.last?.start == startOfWeek())
        #expect(result.slots.last?.distance == 20_000)
        #expect(result.slots.dropLast().last?.distance == 5_000)
    }

    @Test("les créneaux sont contigus, créneaux vides compris")
    func buildsContiguousSlots() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, distance: 30_000, monthsBack: 0),
            // A gap of ten months in between, which has to show as zeros rather
            // than putting the two bars side by side.
            makeActivity(in: context, id: 2, distance: 10_000, monthsBack: 11),
        ]

        let slots = stats(activities).slots

        #expect(slots.count == 12)
        #expect(slots.map(\.start) == slots.map(\.start).sorted())
        #expect(slots.first?.distance == 10_000)
        #expect(slots.last?.distance == 30_000)
        #expect(slots.dropFirst().dropLast().allSatisfy { $0.distance == 0 })
    }

    @Test("la fenêtre se termine sur le créneau courant, pas sur la donnée")
    func endsOnTheCurrentSlot() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // Old data and a short window: the period is a stated range, so it stays
        // put and simply comes back empty rather than chasing the activities.
        let old = makeActivity(in: context, id: 1, monthsBack: 30)

        let result = stats([old], .threeMonths)

        #expect(result.count == 0)
        #expect(result.slots.count == 13)
        #expect(result.slots.last?.start == startOfWeek())
    }

    // MARK: - Comparison

    @Test("l'année en cours se compare à l'année précédente, pas au trimestre")
    func comparesTheCalendarYearAgainstTheYearBefore() {
        // A rolling window compares against the span just before it, counted in
        // its own unit; a calendar year has to shift by twelve months or the
        // comparison would cover a different season entirely.
        #expect(StatsPeriod.threeMonths.comparisonShift(now: reference, calendar: calendar) == 13)
        #expect(StatsPeriod.sixMonths.comparisonShift(now: reference, calendar: calendar) == 26)
        #expect(StatsPeriod.twelveMonths.comparisonShift(now: reference, calendar: calendar) == 12)
        #expect(StatsPeriod.currentYear.comparisonShift(now: reference, calendar: calendar) == 12)
    }

    @Test("la série de comparaison lit la période précédente")
    func readsThePrecedingPeriod() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            // This month, and the same month a year earlier.
            makeActivity(in: context, id: 1, distance: 30_000, monthsBack: 0),
            makeActivity(in: context, id: 2, distance: 12_000, monthsBack: 12),
        ]

        let result = stats(activities, .twelveMonths)

        // The period itself counts only the recent one...
        #expect(result.count == 1)
        // ...while the older one still shows up as the comparison for its slot,
        // which the sidebar's period filter would have removed outright.
        #expect(result.slots.last?.distance == 30_000)
        #expect(result.slots.last?.comparisonDistance == 12_000)
    }

    @Test("la comparaison hebdomadaire lit la même semaine, un cycle plus tôt")
    func readsThePrecedingWeeks() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(in: context, id: 1, distance: 30_000, daysBack: 0),
            // Thirteen weeks earlier, the shift a three-month window uses.
            makeActivity(in: context, id: 2, distance: 9_000, daysBack: 13 * 7),
        ]

        let result = stats(activities, .threeMonths)

        #expect(result.count == 1)
        #expect(result.slots.last?.distance == 30_000)
        #expect(result.slots.last?.comparisonDistance == 9_000)
        #expect(result.slots.last?.comparisonStart == startOfWeek(daysBack: 13 * 7))
    }

    @Test("les cumuls et records ne portent que sur la période")
    func restrictsTotalsToThePeriod() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activities = [
            makeActivity(
                in: context, id: 1, distance: 10_000, daysBack: 14,
                name: "Dans la période"
            ),
            makeActivity(
                in: context, id: 2, distance: 90_000, monthsBack: 8,
                name: "Hors période"
            ),
        ]

        let result = stats(activities, .threeMonths)

        #expect(result.count == 1)
        #expect(result.sports.first?.distance == 10_000)
        #expect(result.records.first { $0.kind == .distance }?.activityName
            == "Dans la période")
    }
}

@Suite("Records cliquables")
@MainActor
struct RecordSelectionTests {
    @Test("chaque record retient l'activité qui le détient")
    func recordsCarryTheirActivity() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_700_200_000)

        let modest = Activity(stravaID: 1, name: "Petite sortie", sportType: .ride)
        modest.distance = 10_000
        modest.startDate = now
        modest.startLocalDate = now
        let best = Activity(stravaID: 2, name: "La grande", sportType: .ride)
        best.distance = 120_000
        best.startDate = now
        best.startLocalDate = now
        [modest, best].forEach(context.insert)
        try context.save()

        let stats = ActivityStatistics.compute(
            for: [modest, best], period: .twelveMonths, now: now
        )
        let record = stats.records.first { $0.kind == .distance }

        // Carried rather than looked up again from the name and the date: two
        // outings can share both, and opening the wrong one would be worse than
        // opening nothing at all.
        #expect(record?.activityName == "La grande")
        #expect(record?.activityID == best.id)
        #expect(record?.activityID != modest.id)
    }
}
