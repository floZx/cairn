import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("Model")
struct ModelTests {
    @Test("une activité survit à un aller-retour en base")
    func persistsActivity() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let activity = Activity(stravaID: 42, name: "Sortie du matin", sportType: .ride)
        activity.distance = 42_195
        activity.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let track = [
            Coordinate(latitude: 45.75, longitude: 4.83),
            Coordinate(latitude: 45.80, longitude: 4.90),
        ]
        activity.apply(simplifiedCoordinates: track)
        activity.apply(boundingBox: BoundingBox(coordinates: track)!)
        context.insert(activity)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Activity>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Sortie du matin")
        #expect(fetched[0].sportType == .ride)
        #expect(fetched[0].simplifiedCoordinates == track)
        #expect(fetched[0].boundingBox == BoundingBox(coordinates: track))
        #expect(fetched[0].minLat == 45.75)
        #expect(fetched[0].maxLon == 4.90)
    }

    @Test("les streams sont liés et relisibles")
    func persistsStreams() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let activity = Activity(stravaID: 7, name: "Test", sportType: .run)
        let streams = ActivityStreams()
        streams.pointCount = 3
        streams.altitude = TrackBlob.encode(scalars: [100, 110, 120])
        streams.activity = activity
        activity.streams = streams
        context.insert(activity)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Activity>())
        let altitude = fetched[0].streams.flatMap { $0.altitude }
        #expect(altitude.map(TrackBlob.decodeScalars) == [100, 110, 120])
    }

    @Test("le type de sport Strava inconnu retombe sur other")
    func mapsUnknownSport() {
        #expect(SportType(stravaValue: "Ride") == .ride)
        #expect(SportType(stravaValue: "TrailRun") == .trailRun)
        #expect(SportType(stravaValue: "Kitesurf") == .other)
    }

    @Test("l'état de synchro persiste sa file d'attente")
    func persistsSyncState() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let state = SyncState()
        state.pendingStreamIDs = [1, 2, 3]
        state.lastSummaryEpoch = 1_700_000_000
        context.insert(state)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SyncState>())
        #expect(fetched[0].pendingStreamIDs == [1, 2, 3])
        #expect(fetched[0].lastSummaryEpoch == 1_700_000_000)
    }
}
