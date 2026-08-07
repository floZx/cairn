import Foundation

/// Cumulative distance along a track, and lookups on it.
///
/// Strava sends a `distance` stream measured by the device, which is the
/// authoritative answer — but it only arrives with a stream fetch. Computing the
/// same axis from coordinates already in the store means activities synced
/// before that stream was imported are just as precise, without spending a
/// single API request re-fetching them.
enum DistanceAxis {
    /// Cumulative metres from the start, one entry per coordinate.
    ///
    /// Uses an equirectangular approximation, the same one the track simplifier
    /// uses: at the spacing between consecutive GPS samples the error is far
    /// below the noise in the samples themselves.
    static func cumulativeMetres(along coordinates: [Coordinate]) -> [Double] {
        guard !coordinates.isEmpty else { return [] }

        let metresPerDegree = 111_200.0
        var distances = [Double](repeating: 0, count: coordinates.count)
        var total = 0.0

        for index in 1..<coordinates.count {
            let previous = coordinates[index - 1]
            let current = coordinates[index]
            let meanLatitude = (previous.latitude + current.latitude) / 2
            let scale = cos(meanLatitude * .pi / 180)

            let dy = (current.latitude - previous.latitude) * metresPerDegree
            let dx = (current.longitude - previous.longitude) * metresPerDegree * scale
            total += (dx * dx + dy * dy).squareRoot()
            distances[index] = total
        }
        return distances
    }

    /// Index of the entry closest to `metres`, or nil for an empty axis.
    ///
    /// The axis is sorted, so this is a binary search: hover moves the cursor
    /// hundreds of times a second over tracks of tens of thousands of points.
    static func nearestIndex(to metres: Double, in distances: [Double]) -> Int? {
        guard !distances.isEmpty else { return nil }
        guard distances.count > 1 else { return 0 }

        var low = 0
        var high = distances.count - 1
        while low < high {
            let middle = (low + high) / 2
            if distances[middle] < metres {
                low = middle + 1
            } else {
                high = middle
            }
        }
        // `low` is the first entry at or past the target; the one before it may
        // be closer.
        guard low > 0 else { return 0 }
        let after = distances[low]
        let before = distances[low - 1]
        return (metres - before) <= (after - metres) ? low - 1 : low
    }
}
