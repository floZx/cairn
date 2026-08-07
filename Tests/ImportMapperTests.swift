import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("ImportMapper")
struct ImportMapperTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("mappe une activité résumée complète")
    func mapsSummary() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")

        let activity = try mapper.upsert(summary: dto)
        try context.save()

        #expect(activity.stravaID == 10_123_456_789)
        #expect(activity.name == "Sortie matinale")
        #expect(activity.sportType == .ride)
        #expect(activity.distance == 45_231.4)
        #expect(activity.movingTime == 5412)
        #expect(activity.totalElevationGain == 612)
        #expect(activity.averageHeartrate == 138.4)
        #expect(activity.weightedAverageWatts == 178)
        #expect(activity.kudosCount == 12)
        #expect(activity.isCommute == false)
        #expect(activity.startLatitude == 45.764043)
        #expect(activity.endLongitude == 4.842)
        #expect(activity.summaryPolyline == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    }

    @Test("la trace simplifiée et la bbox sont dérivées de la polyline de résumé")
    func derivesTrackAndBox() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")

        let activity = try mapper.upsert(summary: dto)

        #expect(activity.hasTrack)
        #expect(activity.simplifiedCoordinates.count >= 2)
        let box = activity.boundingBox
        #expect(box != nil)
        #expect(box!.minLat < box!.maxLat)
        // La polyline de référence va de 38.5 à 43.252 de latitude.
        #expect(abs(box!.minLat - 38.5) < 0.001)
        #expect(abs(box!.maxLat - 43.252) < 0.001)
    }

    @Test("une activité manuelle sans trace reste importable")
    func mapsManualActivity() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "manual_activity")

        let activity = try mapper.upsert(summary: dto)

        #expect(activity.isManual)
        #expect(activity.sportType == .workout)
        #expect(!activity.hasTrack)
        #expect(activity.simplifiedTrack == nil)
        #expect(activity.startLatitude == nil)
        #expect(activity.averageHeartrate == nil)
        #expect(activity.kudosCount == 0)
    }

    @Test("réimporter la même activité met à jour sans dupliquer")
    func upsertIsIdempotent() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")

        _ = try mapper.upsert(summary: dto)
        try context.save()
        let again = try mapper.upsert(summary: dto)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Activity>())
        #expect(all.count == 1)
        #expect(again.persistentModelID == all[0].persistentModelID)
    }

    @Test("les streams sont packés et rattachés")
    func mapsStreams() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let streams = try Fixture.decode(StreamSetDTO.self, "streams")

        mapper.apply(streams: streams, to: activity)
        try context.save()

        #expect(activity.streams?.pointCount == 3)
        #expect(
            activity.streams?.altitude.map(TrackBlob.decodeScalars) == [172.4, 175.1, 180.9]
        )
        #expect(activity.streams?.time.map(TrackBlob.decodeTimes) == [0, 5, 11])
        #expect(activity.streams?.heartrate.map(TrackBlob.decodeScalars) == [96, 104, 118])
        #expect(activity.streams?.watts == nil)
        // moving est un stream de booléens → packé en 0/1
        #expect(activity.streams?.moving.map(TrackBlob.decodeScalars) == [0, 1, 1])
    }

    @Test("le stream latlng remplace la trace simplifiée issue de la polyline")
    func streamsRefineTrack() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        mapper.apply(
            streams: try Fixture.decode(StreamSetDTO.self, "streams"), to: activity
        )

        // Les streams de la fixture sont à Lyon, la polyline de résumé en Californie.
        let box = activity.boundingBox!
        #expect(abs(box.minLat - 45.764043) < 0.001)
        #expect(abs(box.maxLon - 4.837) < 0.001)
        #expect(activity.streams?.coordinates.count == 3)
    }

    @Test("réappliquer des streams ne crée pas un second enregistrement")
    func streamsUpsert() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let streams = try Fixture.decode(StreamSetDTO.self, "streams")

        mapper.apply(streams: streams, to: activity)
        try context.save()
        mapper.apply(streams: streams, to: activity)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ActivityStreams>()).count == 1)
    }

    @Test("le détail ajoute description, calories et laps")
    func mapsDetail() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let detail = DetailActivityDTO(
            id: 10_123_456_789,
            description: "Belle sortie",
            calories: 812,
            device_name: "Garmin Edge 840",
            laps: [
                LapDTO(
                    id: 1, name: "Lap 1", lap_index: 1, distance: 20_000,
                    moving_time: 2600, elapsed_time: 2700, total_elevation_gain: 300,
                    average_speed: 7.7, max_speed: 15, average_heartrate: 135,
                    average_cadence: 80, start_index: 0, end_index: 1500
                )
            ]
        )

        try mapper.apply(detail: detail, to: activity)
        try context.save()

        #expect(activity.activityDescription == "Belle sortie")
        #expect(activity.calories == 812)
        #expect(activity.deviceName == "Garmin Edge 840")
        #expect(activity.detailFetchedAt != nil)
        #expect(activity.laps.count == 1)
        #expect(activity.laps[0].distance == 20_000)
        #expect(activity.laps[0].endIndex == 1500)
    }

    @Test("réappliquer le détail remplace les laps au lieu de les accumuler")
    func detailReplacesLaps() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let lap = LapDTO(
            id: 1, name: "Lap 1", lap_index: 1, distance: 1000, moving_time: 100,
            elapsed_time: 100, total_elevation_gain: 0, average_speed: 10,
            max_speed: 12, average_heartrate: nil, average_cadence: nil,
            start_index: 0, end_index: 10
        )
        let detail = DetailActivityDTO(
            id: 10_123_456_789, description: nil, calories: nil,
            device_name: nil, laps: [lap]
        )

        try mapper.apply(detail: detail, to: activity)
        try context.save()
        try mapper.apply(detail: detail, to: activity)
        try context.save()

        #expect(activity.laps.count == 1)
        #expect(try context.fetch(FetchDescriptor<Lap>()).count == 1)
    }

    @Test("l'athlète est unique et mis à jour")
    func upsertsAthlete() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(AthleteDTO.self, "athlete")

        _ = try mapper.upsert(athlete: dto)
        try context.save()
        let second = try mapper.upsert(athlete: dto)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Athlete>()).count == 1)
        #expect(second.fullName == "Camille Durand")
        #expect(second.city == "Lyon")
    }

    @Test("retrouve une activité par son identifiant Strava")
    func findsByStravaID() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        _ = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        try context.save()

        #expect(try mapper.activity(stravaID: 10_123_456_789) != nil)
        #expect(try mapper.activity(stravaID: 1) == nil)
    }

    @Test("réimporter le résumé après les streams ne dégrade pas la trace")
    func summaryReimportKeepsStreamTrack() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        let activity = try mapper.upsert(summary: dto)
        mapper.apply(
            streams: try Fixture.decode(StreamSetDTO.self, "streams"), to: activity
        )
        try context.save()

        let trackFromStreams = activity.simplifiedCoordinates
        let boxFromStreams = activity.boundingBox

        // The sync engine re-imports summaries on every incremental run.
        _ = try mapper.upsert(summary: dto)
        try context.save()

        #expect(activity.simplifiedCoordinates == trackFromStreams)
        #expect(activity.boundingBox == boxFromStreams)
        // Still Lyon, from the streams — not California, from the summary polyline.
        #expect(abs(activity.boundingBox!.minLat - 45.764043) < 0.001)
    }

    @Test("le matériel est unique et mis à jour au réimport")
    func upsertsGear() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let bike = GearDTO(
            id: "b1234567", name: "Vélo de route", brand_name: "Marque",
            model_name: "Modèle", distance: 12_345
        )

        let first = try mapper.upsert(gear: bike)
        try context.save()
        #expect(first.isBike)
        #expect(first.totalDistance == 12_345)

        let renamed = GearDTO(
            id: "b1234567", name: "Vélo repeint", brand_name: "Marque",
            model_name: "Modèle", distance: 20_000
        )
        let second = try mapper.upsert(gear: renamed)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Gear>()).count == 1)
        #expect(second.name == "Vélo repeint")
        #expect(second.totalDistance == 20_000)

        // A "g" prefix means shoes, not a bike.
        let shoes = try mapper.upsert(
            gear: GearDTO(
                id: "g987", name: "Chaussures", brand_name: nil,
                model_name: nil, distance: 0
            )
        )
        try context.save()
        #expect(!shoes.isBike)
    }

    @Test("elapsedTime dérivé n'écrase pas une durée protégée")
    func elapsedTimeFollowsMovingTimeProtection() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let editedElapsed = activity.elapsedTime
        activity.movingTime = 90 * 60
        activity.markEdited([.movingTime])

        // Strava still thinks the outing lasted the original, shorter time.
        let corrected = try Fixture.decode(
            SummaryActivityDTO.self, from: "summary_activity",
            patching: ["id": activity.stravaID, "elapsed_time": 65 * 60]
        )
        let again = try mapper.upsert(summary: corrected)

        #expect(again.elapsedTime == editedElapsed)
    }

    @Test("averageSpeed dérivée n'écrase pas une distance ou une durée protégée")
    func averageSpeedFollowsDistanceOrMovingTimeProtection() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        activity.distance = 12_000
        activity.markEdited([.distance])
        let editedAverageSpeed = activity.averageSpeed

        // Strava recomputed average speed from its own, uncorrected distance.
        let corrected = try Fixture.decode(
            SummaryActivityDTO.self, from: "summary_activity",
            patching: ["id": activity.stravaID, "average_speed": 99.0]
        )
        let again = try mapper.upsert(summary: corrected)

        #expect(again.averageSpeed == editedAverageSpeed)
    }

    @Test("les streams sans position comptent quand même leurs points")
    func pointCountFromNonPositionStreams() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let heartRateOnly = StreamSetDTO(
            latlng: nil, distance: nil, altitude: nil, time: nil,
            heartrate: StreamDTO(data: [100, 110, 120, 130]),
            cadence: nil, watts: nil, velocity_smooth: nil,
            temp: nil, grade_smooth: nil, moving: nil
        )
        mapper.apply(streams: heartRateOnly, to: activity)
        try context.save()

        #expect(activity.streams?.pointCount == 4)
    }
}
