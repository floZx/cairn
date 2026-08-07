import Foundation
import SwiftData

/// Turns a parsed GPX track into an activity in the journal.
///
/// Everything Strava would have sent ready-made has to be computed here:
/// distance, climbing, moving time. `TrackMetrics` owns those decisions; this
/// type owns the mapping into the model.
struct GPXImporter {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Builds the activity, inserts it, and returns it. Saving stays with the
    /// caller, which is the only place that can report a failure to the user.
    @discardableResult
    func `import`(_ track: GPXTrack, fallbackName: String) throws -> Activity {
        let coordinates = track.coordinates
        guard !coordinates.isEmpty else { throw GPXError.noPoints }

        let name = track.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = Activity(
            // Zero, like a hand-entered activity: `stravaID` identifies a
            // Strava activity, and this one has no counterpart there.
            stravaID: 0,
            name: name?.isEmpty == false ? name! : fallbackName,
            sportType: Self.sport(for: track.type)
        )
        activity.source = .file

        let times = track.times
        let start = times.first ?? Date()
        activity.startDate = start
        // A GPX timestamp is UTC and says nothing about where the outing
        // happened, so the wall time is reconstructed with this Mac's offset.
        // Wrong for a track recorded abroad, and knowably so — but leaving the
        // two equal would silently place every import in UTC, which is wrong
        // for everyone who is not in it.
        activity.startLocalDate = start.addingTimeInterval(
            Double(TimeZone.current.secondsFromGMT(for: start))
        )
        activity.timezoneIdentifier = TimeZone.current.identifier

        activity.distance = TrackMetrics.distance(of: coordinates)
        activity.totalElevationGain = TrackMetrics.elevationGain(of: track.elevations)
        activity.elapsedTime = TrackMetrics.elapsedTime(times)
        activity.movingTime = TrackMetrics.movingTime(
            coordinates: coordinates, times: times
        )
        activity.averageSpeed = activity.movingTime > 0
            ? activity.distance / Double(activity.movingTime)
            : 0

        let streams = ActivityStreams()
        streams.activity = activity
        streams.latlng = TrackBlob.encode(coordinates: coordinates)
        // Only when every point has one: a half-filled series would put
        // altitudes against the wrong points in every chart that reads it.
        if track.elevations.count == coordinates.count {
            streams.altitude = TrackBlob.encode(
                scalars: track.elevations.map(Float.init)
            )
        }
        if times.count == coordinates.count {
            streams.time = TrackBlob.encode(
                times: times.map { Int32($0.timeIntervalSince(start).rounded()) }
            )
        }
        streams.pointCount = coordinates.count

        activity.streams = streams
        if let box = BoundingBox(coordinates: coordinates) {
            activity.apply(simplifiedCoordinates: Simplify.douglasPeucker(coordinates))
            activity.apply(boundingBox: box)
        }
        activity.detailFetchedAt = Date()

        context.insert(activity)
        context.insert(streams)
        return activity
    }

    /// GPX `<type>` has no controlled vocabulary, so this reads the common
    /// spellings and gives up gracefully rather than pretending to know.
    ///
    /// `.other` is a fine landing place: the activity is in the journal, and the
    /// editor is one click away.
    static func sport(for type: String?) -> SportType {
        guard let type = type?.lowercased() else { return .other }
        // Substring matching on purpose: exporters write "Running", "9" (Garmin's
        // numeric code), "cycling - road", and everything in between.
        let table: [(needle: String, sport: SportType)] = [
            ("trail", .trailRun), ("run", .run), ("jog", .run),
            ("mountain", .mountainBikeRide), ("mtb", .mountainBikeRide),
            ("gravel", .gravelRide),
            ("cycl", .ride), ("bike", .ride), ("ride", .ride), ("velo", .ride),
            ("hik", .hike), ("rando", .hike),
            ("walk", .walk), ("marche", .walk),
            ("swim", .swim), ("nat", .swim),
            ("ski", .nordicSki),
            ("row", .rowing), ("kayak", .rowing),
        ]
        return table.first { type.contains($0.needle) }?.sport ?? .other
    }
}
