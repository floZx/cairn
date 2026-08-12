import Foundation

/// Everything the detail view derives from an activity's stored blobs: the
/// track, the cumulative-distance axis, and the chart series.
///
/// Deriving these is O(n) over the raw streams — decoding blobs, walking
/// coordinates, downsampling four series. The detail view re-evaluates its body
/// on every mouse move while a chart is hovered, so doing that work in computed
/// properties made every hover event pay the full cost again. Built once here,
/// cached per activity, and rebuilt only when the underlying data changes.
struct ActivityTrackModel {
    let coordinates: [Coordinate]
    let distancesMetres: [Double]
    let series: [StreamSeries]

    /// The point of the track nearest a distance from the start, or nil when
    /// there is no track to speak of.
    func coordinate(atKilometre km: Double) -> Coordinate? {
        guard coordinates.count > 1 else { return nil }
        guard let index = DistanceAxis.nearestIndex(
            to: km * 1000, in: distancesMetres
        ) else { return nil }
        return coordinates[min(index, coordinates.count - 1)]
    }

    static func build(for activity: Activity) -> ActivityTrackModel {
        let coordinates = activity.displayCoordinates

        // Strava's own distance stream when it was synced, otherwise computed
        // from the coordinates already in the store — so activities imported
        // before that stream existed are just as precise, with no API request
        // spent.
        let distances: [Double]
        if let blob = activity.streams?.distance {
            let measured = TrackBlob.decodeScalars(blob).map(Double.init)
            distances = measured.count == coordinates.count
                ? measured
                : DistanceAxis.cumulativeMetres(along: coordinates)
        } else {
            distances = DistanceAxis.cumulativeMetres(along: coordinates)
        }

        return ActivityTrackModel(
            coordinates: coordinates,
            distancesMetres: distances,
            series: StreamSeriesBuilder.series(
                from: activity.streams,
                totalDistance: activity.distance,
                distancesMetres: distances,
                sport: activity.sportType
            )
        )
    }
}

/// Small per-activity cache for `ActivityTrackModel`.
///
/// Keyed by Strava id and validated by a fingerprint of the stored data, so a
/// stream arriving from phase B of the sync — or a resync refreshing the
/// simplified track — rebuilds the model instead of serving a stale one.
@MainActor
enum ActivityTrackModelCache {
    /// The stored facts the model is derived from. If none of these moved, the
    /// cached model is still true.
    private struct Fingerprint: Equatable {
        let pointCount: Int
        let simplifiedByteCount: Int
        let hasDistanceStream: Bool
        let totalDistance: Double
        /// Here because the cadence series is scaled by sport: correcting a
        /// ride imported as a run has to redraw it, not serve the rpm version.
        let sportRaw: String

        init(of activity: Activity) {
            pointCount = activity.streams?.pointCount ?? -1
            simplifiedByteCount = activity.simplifiedTrack?.count ?? 0
            hasDistanceStream = activity.streams?.distance != nil
            totalDistance = activity.distance
            sportRaw = activity.sportTypeRaw
        }
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let model: ActivityTrackModel
    }

    /// A handful of entries covers flipping between recently viewed activities;
    /// beyond that, rebuilding is cheap enough.
    private static let capacity = 8
    private static var entries: [Int64: Entry] = [:]
    /// Least recently used first.
    private static var order: [Int64] = []

    /// How many times a model was actually built. Exists so tests can observe
    /// caching behaviour without reaching into the storage.
    private(set) static var buildCount = 0

    static func model(for activity: Activity) -> ActivityTrackModel {
        let key = activity.stravaID
        let fingerprint = Fingerprint(of: activity)

        if let entry = entries[key], entry.fingerprint == fingerprint {
            touch(key)
            return entry.model
        }

        let model = ActivityTrackModel.build(for: activity)
        buildCount += 1
        entries[key] = Entry(fingerprint: fingerprint, model: model)
        touch(key)
        evictIfNeeded()
        return model
    }

    static func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    private static func touch(_ key: Int64) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private static func evictIfNeeded() {
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            entries[oldest] = nil
        }
    }
}
