import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("ActivityFilter")
struct ActivityFilterTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeContext(_ configure: (ModelContext) throws -> Void) throws
        -> ModelContext
    {
        let context = ModelContext(try AppModelContainer.inMemory())
        try configure(context)
        try context.save()
        return context
    }

    private func insert(
        _ context: ModelContext, id: Int64, name: String = "Sortie",
        sport: SportType = .ride, daysAgo: Int = 1, distance: Double = 30_000,
        duration: Int = 3600, elevation: Double = 200,
        track: [Coordinate] = [Coordinate(latitude: 45.75, longitude: 4.83)]
    ) {
        let activity = Activity(stravaID: id, name: name, sportType: sport)
        activity.startDate = now.addingTimeInterval(Double(-daysAgo * 86_400))
        activity.startLocalDate = activity.startDate
        activity.distance = distance
        activity.movingTime = duration
        activity.elapsedTime = duration
        activity.totalElevationGain = elevation
        activity.apply(simplifiedCoordinates: track)
        if let box = BoundingBox(coordinates: track) { activity.apply(boundingBox: box) }
        context.insert(activity)
    }

    private func fetch(_ context: ModelContext, _ filter: ActivityFilter) throws
        -> [Activity]
    {
        try context
            .fetch(FetchDescriptor<Activity>(predicate: filter.predicate(now: now)))
            .filter(filter.matchesPrecisely)
    }

    @Test("le filtre vide laisse tout passer")
    func emptyFilterMatchesAll() throws {
        let context = try makeContext {
            insert($0, id: 1)
            insert($0, id: 2, sport: .run)
        }
        #expect(try fetch(context, .none).count == 2)
    }

    @Test("filtre par sport")
    func filtersBySport() throws {
        let context = try makeContext {
            insert($0, id: 1, sport: .ride)
            insert($0, id: 2, sport: .run)
            insert($0, id: 3, sport: .trailRun)
        }
        var filter = ActivityFilter.none
        filter.sports = [.run, .trailRun]
        #expect(try fetch(context, filter).count == 2)
    }

    @Test("filtre par texte, insensible à la casse")
    func filtersBySearchText() throws {
        let context = try makeContext {
            insert($0, id: 1, name: "Col de la Croix")
            insert($0, id: 2, name: "Footing matinal")
        }
        var filter = ActivityFilter.none
        filter.searchText = "croix"
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("filtre par période")
    func filtersByPeriod() throws {
        let context = try makeContext {
            insert($0, id: 1, daysAgo: 5)
            insert($0, id: 2, daysAgo: 200)
        }
        var filter = ActivityFilter.none
        filter.period = .last30Days
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("filtre par plage de distance")
    func filtersByDistance() throws {
        let context = try makeContext {
            insert($0, id: 1, distance: 5_000)
            insert($0, id: 2, distance: 50_000)
            insert($0, id: 3, distance: 120_000)
        }
        var filter = ActivityFilter.none
        filter.minDistanceKm = 20
        filter.maxDistanceKm = 100
        #expect(try fetch(context, filter).map(\.stravaID) == [2])
    }

    @Test("filtre par durée minimale et dénivelé minimal")
    func filtersByDurationAndElevation() throws {
        let context = try makeContext {
            insert($0, id: 1, duration: 1200, elevation: 50)
            insert($0, id: 2, duration: 7200, elevation: 1500)
        }
        var filter = ActivityFilter.none
        filter.minDurationMinutes = 60
        filter.minElevation = 1000
        #expect(try fetch(context, filter).map(\.stravaID) == [2])
    }

    @Test("les filtres se combinent")
    func combinesFilters() throws {
        let context = try makeContext {
            insert($0, id: 1, name: "Sortie longue", sport: .ride, distance: 120_000)
            insert($0, id: 2, name: "Sortie longue", sport: .run, distance: 30_000)
            insert($0, id: 3, name: "Sortie courte", sport: .ride, distance: 120_000)
        }
        var filter = ActivityFilter.none
        filter.searchText = "longue"
        filter.sports = [.ride]
        filter.minDistanceKm = 100
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("le filtre par région écarte les traces hors zone")
    func filtersByRegion() throws {
        let context = try makeContext {
            insert(
                $0, id: 1,
                track: [
                    Coordinate(latitude: 45.75, longitude: 4.83),
                    Coordinate(latitude: 45.78, longitude: 4.88),
                ]
            )
            insert(
                $0, id: 2,
                track: [Coordinate(latitude: 48.85, longitude: 2.35)]
            )
        }
        var filter = ActivityFilter.none
        filter.region = BoundingBox(
            minLat: 45.74, maxLat: 45.76, minLon: 4.82, maxLon: 4.84
        )
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("une bbox qui chevauche mais dont aucun point n'entre est écartée")
    func regionRejectsBoxOnlyOverlap() throws {
        // Trace en L : sa bbox couvre le coin visé, mais aucun point n'y passe.
        let context = try makeContext {
            insert(
                $0, id: 1,
                track: [
                    Coordinate(latitude: 45.70, longitude: 4.80),
                    Coordinate(latitude: 45.70, longitude: 4.90),
                    Coordinate(latitude: 45.80, longitude: 4.90),
                ]
            )
        }
        var filter = ActivityFilter.none
        filter.region = BoundingBox(
            minLat: 45.79, maxLat: 45.81, minLon: 4.79, maxLon: 4.81
        )
        #expect(try fetch(context, filter).isEmpty)
    }

    @Test("une activité sans trace n'apparaît jamais dans une recherche par région")
    func regionExcludesTracklessActivities() throws {
        let context = try makeContext { insert($0, id: 1, track: []) }
        var filter = ActivityFilter.none
        filter.region = BoundingBox.world
        #expect(try fetch(context, filter).isEmpty)
    }

    @Test("isActive distingue un filtre vide d'un filtre en cours")
    func reportsActivity() {
        #expect(!ActivityFilter.none.isActive)
        var filter = ActivityFilter.none
        filter.sports = [.run]
        #expect(filter.isActive)
    }

    @Test("les périodes calculent des bornes cohérentes")
    func computesPeriodBounds() {
        #expect(DatePeriod.all.startDate(now: now) == nil)
        #expect(DatePeriod.last30Days.startDate(now: now) != nil)
        #expect(DatePeriod.last30Days.startDate(now: now)! < now)
        #expect(DatePeriod.lastYear.endDate(now: now) != nil)
        #expect(DatePeriod.thisYear.endDate(now: now) == nil)
    }
}
