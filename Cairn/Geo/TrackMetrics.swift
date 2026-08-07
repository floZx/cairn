import Foundation

/// The figures a recorded track carries implicitly: how far, how high, how long.
///
/// Strava sends these ready-made, so nothing needed them until a GPX file
/// arrived with nothing but points.
enum TrackMetrics {
    /// Total length of the track, in metres.
    static func distance(of coordinates: [Coordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst())
            .reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Below this, a change in altitude is treated as GPS noise.
    ///
    /// Barometric and GPS altitude both wander by a metre or two while standing
    /// still. Summing every positive delta would turn that wander into hundreds
    /// of metres of climbing on a flat ride — the single most common way a
    /// home-made elevation figure goes wrong.
    static let elevationNoiseFloor: Double = 3

    /// Metres climbed, counting only rises that clear the noise floor.
    ///
    /// Hysteresis rather than a per-sample filter: the reference only moves once
    /// the profile has genuinely departed from it, so a long steady climb made
    /// of centimetre steps still counts in full, while a flat section that
    /// jitters by two metres counts for nothing.
    static func elevationGain(
        of altitudes: [Double], noiseFloor: Double = elevationNoiseFloor
    ) -> Double {
        guard var reference = altitudes.first else { return 0 }
        var gain: Double = 0
        for altitude in altitudes.dropFirst() {
            let delta = altitude - reference
            guard abs(delta) >= noiseFloor else { continue }
            if delta > 0 { gain += delta }
            reference = altitude
        }
        return gain
    }

    /// Under this speed, the athlete counts as stopped.
    ///
    /// 0.5 m/s is 1.8 km/h — slower than a stroll, so it catches red lights and
    /// summit breaks without discarding a genuinely slow walk uphill.
    static let movingSpeedFloor: Double = 0.5

    /// Seconds spent actually moving, from paired points and timestamps.
    ///
    /// Falls back to the elapsed span when the two series don't line up: a
    /// wrong-but-plausible moving time is worse than the honest total.
    static func movingTime(
        coordinates: [Coordinate], times: [Date], speedFloor: Double = movingSpeedFloor
    ) -> Int {
        guard coordinates.count == times.count, times.count > 1 else {
            return elapsedTime(times)
        }
        var moving: Double = 0
        for index in 1..<times.count {
            let interval = times[index].timeIntervalSince(times[index - 1])
            guard interval > 0 else { continue }
            let step = coordinates[index - 1].distance(to: coordinates[index])
            if step / interval >= speedFloor { moving += interval }
        }
        return Int(moving.rounded())
    }

    /// Seconds between the first and last timestamp.
    static func elapsedTime(_ times: [Date]) -> Int {
        guard let first = times.first, let last = times.last else { return 0 }
        return max(0, Int(last.timeIntervalSince(first).rounded()))
    }
}

extension Coordinate {
    /// Great-circle distance in metres.
    ///
    /// Haversine rather than the flat approximation `Simplify` uses: that one
    /// compares a point to a segment a few metres long, where the error is
    /// invisible, whereas this one is summed over thousands of steps and any
    /// bias accumulates into the activity's headline figure.
    func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}
