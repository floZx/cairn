import Foundation
import SwiftData

@Model
final class Activity {
    #Index<Activity>([\.startDate], [\.stravaID], [\.minLat], [\.maxLat], [\.minLon], [\.maxLon])
    #Unique<Activity>([\.stravaID])

    var stravaID: Int64 = 0
    var name: String = ""
    var sportTypeRaw: String = SportType.other.rawValue
    var startDate: Date = Date.distantPast
    var startLocalDate: Date = Date.distantPast
    var timezoneIdentifier: String?

    var distance: Double = 0
    var movingTime: Int = 0
    var elapsedTime: Int = 0
    var totalElevationGain: Double = 0
    var averageSpeed: Double = 0
    var maxSpeed: Double = 0
    var averageHeartrate: Double?
    var maxHeartrate: Double?
    var averageWatts: Double?
    var weightedAverageWatts: Double?
    var kilojoules: Double?
    var averageCadence: Double?
    var calories: Double?

    var isCommute: Bool = false
    var isTrainer: Bool = false
    var isManual: Bool = false
    var isPrivate: Bool = false

    var kudosCount: Int = 0
    var achievementCount: Int = 0
    var prCount: Int = 0
    var athleteCount: Int = 1

    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?

    /// Bounding box of the track, flattened into indexed columns so a
    /// geographic query can be pre-filtered by the database itself.
    /// `world` when the activity has no track (manual entries, indoor trainer).
    var minLat: Double = -90
    var maxLat: Double = 90
    var minLon: Double = -180
    var maxLon: Double = 180
    var hasTrack: Bool = false

    /// Douglas-Peucker-simplified track, packed by `TrackBlob`. Duplicated from
    /// the streams on purpose: it lets the global map and geographic search read
    /// every activity without ever loading a full stream.
    var simplifiedTrack: Data?

    var summaryPolyline: String?
    var activityDescription: String?
    var deviceName: String?
    /// Non-nil once the detail endpoint has been fetched for this activity.
    var detailFetchedAt: Date?

    /// Kept alongside the relationship: the summary endpoint gives us a gear id
    /// long before the gear itself is fetched, and without storing it there'd be
    /// nothing left to link against afterwards.
    var gearID: String?
    var gear: Gear?
    @Relationship(deleteRule: .cascade, inverse: \Lap.activity)
    var laps: [Lap] = []
    @Relationship(deleteRule: .cascade, inverse: \ActivityStreams.activity)
    var streams: ActivityStreams?

    init(stravaID: Int64, name: String, sportType: SportType) {
        self.stravaID = stravaID
        self.name = name
        self.sportTypeRaw = sportType.rawValue
    }

    var sportType: SportType {
        get { SportType(rawValue: sportTypeRaw) ?? .other }
        set { sportTypeRaw = newValue.rawValue }
    }

    var boundingBox: BoundingBox? {
        guard hasTrack else { return nil }
        return BoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    func apply(boundingBox box: BoundingBox) {
        minLat = box.minLat
        maxLat = box.maxLat
        minLon = box.minLon
        maxLon = box.maxLon
        hasTrack = true
    }

    var simplifiedCoordinates: [Coordinate] {
        simplifiedTrack.map(TrackBlob.decodeCoordinates) ?? []
    }

    func apply(simplifiedCoordinates coordinates: [Coordinate]) {
        simplifiedTrack = coordinates.isEmpty ? nil : TrackBlob.encode(coordinates: coordinates)
    }
}
