import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("ActivityTrackModel")
@MainActor
struct ActivityTrackModelTests {
    /// A three-point activity with streams: track, measured distances, altitude.
    private func makeActivity(in context: ModelContext, id: Int64) -> Activity {
        let activity = Activity(stravaID: id, name: "Sortie", sportType: .ride)
        activity.distance = 200

        let track = [
            Coordinate(latitude: 45.75, longitude: 4.83),
            Coordinate(latitude: 45.751, longitude: 4.831),
            Coordinate(latitude: 45.752, longitude: 4.832),
        ]
        let streams = ActivityStreams()
        streams.pointCount = 3
        streams.latlng = TrackBlob.encode(coordinates: track)
        streams.distance = TrackBlob.encode(scalars: [0, 100, 200])
        streams.altitude = TrackBlob.encode(scalars: [372, 380, 375])
        streams.activity = activity
        activity.streams = streams
        context.insert(activity)
        return activity
    }

    @Test("le modèle expose la trace, l'axe mesuré et les séries")
    func buildsFromStreams() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 1)

        let model = ActivityTrackModel.build(for: activity)

        #expect(model.coordinates.count == 3)
        // The device-measured axis wins over the computed one.
        #expect(model.distancesMetres == [0, 100, 200])
        #expect(model.series.map(\.id) == ["altitude"])
        // Halfway along the ride is the middle point.
        #expect(
            model.coordinate(atKilometre: 0.1)
                == Coordinate(latitude: 45.751, longitude: 4.831)
        )
    }

    @Test("sans distance mesurée, l'axe est calculé depuis les coordonnées")
    func fallsBackToComputedAxis() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 2)
        activity.streams?.distance = nil

        let model = ActivityTrackModel.build(for: activity)

        #expect(model.distancesMetres.count == 3)
        #expect(model.distancesMetres[0] == 0)
        #expect(model.distancesMetres[2] > model.distancesMetres[1])
    }

    @Test("le cache ne reconstruit pas tant que rien n'a changé")
    func cacheReusesUntouchedModels() throws {
        ActivityTrackModelCache.removeAll()
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 3)

        let before = ActivityTrackModelCache.buildCount
        _ = ActivityTrackModelCache.model(for: activity)
        _ = ActivityTrackModelCache.model(for: activity)
        _ = ActivityTrackModelCache.model(for: activity)

        #expect(ActivityTrackModelCache.buildCount == before + 1)
    }

    @Test("l'arrivée des streams invalide le modèle en cache")
    func cacheRebuildsWhenStreamsChange() throws {
        ActivityTrackModelCache.removeAll()
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 4)

        let before = ActivityTrackModelCache.buildCount
        _ = ActivityTrackModelCache.model(for: activity)

        // Phase B lands richer streams: same activity, more points.
        let track = (0..<5).map {
            Coordinate(latitude: 45.75 + Double($0) * 0.001, longitude: 4.83)
        }
        activity.streams?.latlng = TrackBlob.encode(coordinates: track)
        activity.streams?.distance = nil
        activity.streams?.pointCount = 5

        let rebuilt = ActivityTrackModelCache.model(for: activity)

        #expect(ActivityTrackModelCache.buildCount == before + 2)
        #expect(rebuilt.coordinates.count == 5)
    }

    @Test("le cache évince les entrées les plus anciennes au-delà de sa capacité")
    func cacheEvictsBeyondCapacity() throws {
        ActivityTrackModelCache.removeAll()
        let context = ModelContext(try AppModelContainer.inMemory())
        let first = makeActivity(in: context, id: 100)
        _ = ActivityTrackModelCache.model(for: first)

        // Push well past the capacity of 8 with other activities.
        for id in Int64(101)...115 {
            _ = ActivityTrackModelCache.model(
                for: makeActivity(in: context, id: id)
            )
        }

        // The first entry was evicted, so asking again rebuilds it.
        let before = ActivityTrackModelCache.buildCount
        _ = ActivityTrackModelCache.model(for: first)
        #expect(ActivityTrackModelCache.buildCount == before + 1)
    }
}
