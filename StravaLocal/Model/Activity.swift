import Foundation
import SwiftData

@Model
final class Activity {
    // No uniqueness constraint any more. An activity created here has no Strava
    // identifier, and several zeroes would violate one — while *changing* a
    // constraint is exactly what turns a lightweight SwiftData migration into a
    // store that will not open. Removing one is safe; adding one is not.
    // Uniqueness of `stravaID` is guaranteed where it always really was: the
    // fetch-or-create in `ImportMapper`, covered by a re-import test.
    #Index<Activity>([\.startDate], [\.stravaID], [\.uuid], [\.minLat], [\.maxLat], [\.minLon], [\.maxLon])

    var stravaID: Int64 = 0
    /// Stable local identity, independent of Strava. Assigned once, at creation.
    var uuid: String = UUID().uuidString
    var sourceRaw: String = ActivitySource.strava.rawValue
    /// Raw keys of `ActivityField`, persisted. See `editedFields`.
    var editedFieldsRaw: [String] = []
    var editedAt: Date?
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
    /// Strava's `workout_type`. Kept raw because its meaning depends on the
    /// sport; `ActivityLabel.fromWorkoutType` does the interpretation.
    var workoutType: Int?

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

    var source: ActivitySource {
        get { ActivitySource(rawValue: sourceRaw) ?? .strava }
        set { sourceRaw = newValue.rawValue }
    }

    /// The fields the user has edited, which the sync must leave alone.
    ///
    /// Unknown raw values are dropped rather than trapped on: a store written by
    /// a later version must still open in an older build.
    var editedFields: Set<ActivityField> {
        get { Set(editedFieldsRaw.compactMap(ActivityField.init(rawValue:))) }
        set { editedFieldsRaw = newValue.map(\.rawValue).sorted() }
    }

    func isEdited(_ field: ActivityField) -> Bool { editedFields.contains(field) }

    /// Adds to what the user has already claimed rather than replacing it: two
    /// successive edits of different fields must both stay protected.
    func markEdited(_ fields: Set<ActivityField>) {
        guard !fields.isEmpty else { return }
        editedFields = editedFields.union(fields)
        editedAt = Date()
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

    /// The markers set on this activity, in a stable order for display.
    var labels: [ActivityLabel] {
        var found: [ActivityLabel] = []
        if let fromType = ActivityLabel.fromWorkoutType(workoutType) {
            found.append(fromType)
        }
        if isCommute { found.append(.commute) }
        if isTrainer { found.append(.trainer) }
        if isManual { found.append(.manual) }
        if isPrivate { found.append(.isPrivate) }
        return found
    }

    /// Metres of climbing per kilometre — the usual way to compare how hilly
    /// two outings were, independently of their length. Zero for an activity
    /// with no distance (a pool swim, a gym session), which is honest: there was
    /// no climbing to spread over any distance.
    var elevationPerKilometre: Double {
        distance > 0 ? totalElevationGain / (distance / 1000) : 0
    }

    /// Average heart rate as a sortable value, zero when none was recorded.
    ///
    /// `Optional` is not `Comparable`, so a table column cannot sort on
    /// `averageHeartrate` directly. Zero puts the monitor-less activities at one
    /// end of the sort rather than scattering them.
    var averageHeartrateOrZero: Double { averageHeartrate ?? 0 }

    /// The best track available for display: the full-resolution stream once it
    /// has been synced, the simplified track until then.
    var displayCoordinates: [Coordinate] {
        let detailed = streams?.coordinates ?? []
        return detailed.isEmpty ? simplifiedCoordinates : detailed
    }

    var simplifiedCoordinates: [Coordinate] {
        simplifiedTrack.map(TrackBlob.decodeCoordinates) ?? []
    }

    func apply(simplifiedCoordinates coordinates: [Coordinate]) {
        simplifiedTrack = coordinates.isEmpty ? nil : TrackBlob.encode(coordinates: coordinates)
    }
}
