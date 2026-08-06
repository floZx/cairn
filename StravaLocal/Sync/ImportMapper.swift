import Foundation
import SwiftData

/// The single bridge between Strava DTOs and SwiftData models.
///
/// Every method is an upsert keyed on the Strava identifier, which is what makes
/// an interrupted sync safe to simply run again.
struct ImportMapper {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func activity(stravaID: Int64) throws -> Activity? {
        var descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.stravaID == stravaID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func upsert(summary dto: SummaryActivityDTO) throws -> Activity {
        let activity = try activity(stravaID: dto.id)
            ?? {
                let new = Activity(
                    stravaID: dto.id, name: dto.name,
                    sportType: SportType(stravaValue: dto.sport_type)
                )
                context.insert(new)
                return new
            }()

        activity.name = dto.name
        activity.sportType = SportType(stravaValue: dto.sport_type)
        activity.startDate = dto.start_date
        activity.startLocalDate = dto.start_date_local
        activity.timezoneIdentifier = dto.timezone

        activity.distance = dto.distance
        activity.movingTime = dto.moving_time
        activity.elapsedTime = dto.elapsed_time
        activity.totalElevationGain = dto.total_elevation_gain
        activity.averageSpeed = dto.average_speed
        activity.maxSpeed = dto.max_speed
        activity.averageHeartrate = dto.average_heartrate
        activity.maxHeartrate = dto.max_heartrate
        activity.averageWatts = dto.average_watts
        activity.weightedAverageWatts = dto.weighted_average_watts
        activity.kilojoules = dto.kilojoules
        activity.averageCadence = dto.average_cadence

        activity.isCommute = dto.commute ?? false
        activity.isTrainer = dto.trainer ?? false
        activity.isManual = dto.manual ?? false
        activity.isPrivate = dto.private ?? false

        activity.kudosCount = dto.kudos_count ?? 0
        activity.achievementCount = dto.achievement_count ?? 0
        activity.prCount = dto.pr_count ?? 0
        activity.athleteCount = dto.athlete_count ?? 1

        let start = Self.coordinate(dto.start_latlng)
        let end = Self.coordinate(dto.end_latlng)
        activity.startLatitude = start?.latitude
        activity.startLongitude = start?.longitude
        activity.endLatitude = end?.latitude
        activity.endLongitude = end?.longitude

        activity.summaryPolyline = dto.map?.summary_polyline

        if let gearID = dto.gear_id, !gearID.isEmpty {
            activity.gearID = gearID
            activity.gear = try existingGear(stravaID: gearID)
        }

        // Only derive the track from the summary polyline while the real streams
        // are still missing — they produce a strictly better track.
        if activity.streams?.latlng == nil {
            applyTrack(from: dto.map?.summary_polyline, to: activity)
        }
        return activity
    }

    func apply(detail dto: DetailActivityDTO, to activity: Activity) throws {
        activity.activityDescription = dto.description
        activity.calories = dto.calories
        activity.deviceName = dto.device_name
        activity.detailFetchedAt = Date()

        // Laps are replaced wholesale: they're cheap, and diffing them would be
        // more code than it saves.
        for lap in activity.laps { context.delete(lap) }
        activity.laps = []

        for lapDTO in dto.laps ?? [] {
            let lap = Lap(stravaID: lapDTO.id, lapIndex: lapDTO.lap_index)
            lap.name = lapDTO.name ?? "Tour \(lapDTO.lap_index)"
            lap.distance = lapDTO.distance
            lap.movingTime = lapDTO.moving_time
            lap.elapsedTime = lapDTO.elapsed_time
            lap.totalElevationGain = lapDTO.total_elevation_gain ?? 0
            lap.averageSpeed = lapDTO.average_speed ?? 0
            lap.maxSpeed = lapDTO.max_speed ?? 0
            lap.averageHeartrate = lapDTO.average_heartrate
            lap.averageCadence = lapDTO.average_cadence
            lap.startIndex = lapDTO.start_index ?? 0
            lap.endIndex = lapDTO.end_index ?? 0
            lap.activity = activity
            context.insert(lap)
            activity.laps.append(lap)
        }
    }

    func apply(streams dto: StreamSetDTO, to activity: Activity) {
        let streams = activity.streams ?? {
            let new = ActivityStreams()
            new.activity = activity
            context.insert(new)
            activity.streams = new
            return new
        }()

        let coordinates = (dto.latlng?.data ?? []).compactMap { pair -> Coordinate? in
            guard pair.count == 2 else { return nil }
            return Coordinate(latitude: pair[0], longitude: pair[1])
        }

        streams.latlng = coordinates.isEmpty
            ? nil : TrackBlob.encode(coordinates: coordinates)
        streams.altitude = Self.pack(dto.altitude?.data)
        streams.heartrate = Self.pack(dto.heartrate?.data)
        streams.cadence = Self.pack(dto.cadence?.data)
        streams.watts = Self.pack(dto.watts?.data)
        streams.velocitySmooth = Self.pack(dto.velocity_smooth?.data)
        streams.temp = Self.pack(dto.temp?.data)
        streams.grade = Self.pack(dto.grade_smooth?.data)
        streams.moving = Self.pack(dto.moving?.data.map { $0 ? 1.0 : 0.0 })
        streams.time = dto.time?.data.map { Int32($0) }
            .nonEmpty.map(TrackBlob.encode(times:))
        streams.pointCount = max(
            coordinates.count,
            dto.time?.data.count ?? dto.altitude?.data.count ?? 0
        )

        if !coordinates.isEmpty {
            applyTrack(coordinates: coordinates, to: activity)
        }
    }

    @discardableResult
    func upsert(athlete dto: AthleteDTO) throws -> Athlete {
        let stravaID = dto.id
        var descriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.stravaID == stravaID }
        )
        descriptor.fetchLimit = 1
        let athlete = try context.fetch(descriptor).first
            ?? {
                let new = Athlete(stravaID: stravaID)
                context.insert(new)
                return new
            }()

        athlete.firstName = dto.firstname ?? ""
        athlete.lastName = dto.lastname ?? ""
        athlete.city = dto.city
        athlete.country = dto.country
        athlete.profileImageURL = dto.profile
        athlete.weight = dto.weight
        athlete.updatedAt = Date()
        return athlete
    }

    @discardableResult
    func upsert(gear dto: GearDTO) throws -> Gear {
        let gear = try existingGear(stravaID: dto.id) ?? {
            let new = Gear(stravaID: dto.id, name: dto.name)
            context.insert(new)
            return new
        }()
        gear.name = dto.name
        gear.brandName = dto.brand_name
        gear.modelName = dto.model_name
        gear.isBike = dto.id.hasPrefix("b")
        gear.totalDistance = dto.distance ?? 0
        return gear
    }

    // MARK: - Helpers

    private func existingGear(stravaID: String) throws -> Gear? {
        var descriptor = FetchDescriptor<Gear>(
            predicate: #Predicate { $0.stravaID == stravaID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func applyTrack(from polyline: String?, to activity: Activity) {
        guard let polyline, !polyline.isEmpty else { return }
        applyTrack(coordinates: Polyline.decode(polyline), to: activity)
    }

    private func applyTrack(coordinates: [Coordinate], to activity: Activity) {
        guard let box = BoundingBox(coordinates: coordinates) else { return }
        activity.apply(simplifiedCoordinates: Simplify.douglasPeucker(coordinates))
        activity.apply(boundingBox: box)
    }

    private static func coordinate(_ pair: [Double]?) -> Coordinate? {
        guard let pair, pair.count == 2 else { return nil }
        return Coordinate(latitude: pair[0], longitude: pair[1])
    }

    private static func pack(_ values: [Double]?) -> Data? {
        guard let values, !values.isEmpty else { return nil }
        return TrackBlob.encode(scalars: values.map(Float.init))
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
