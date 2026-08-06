import Foundation

/// Ramer–Douglas–Peucker line simplification, plus series downsampling.
enum Simplify {
    /// 15 m keeps city streets distinguishable while cutting a typical ride
    /// track by an order of magnitude.
    static let defaultToleranceMeters: Double = 15

    static func douglasPeucker(
        _ coordinates: [Coordinate],
        toleranceMeters: Double = defaultToleranceMeters
    ) -> [Coordinate] {
        guard coordinates.count > 2 else { return coordinates }
        var keep = [Bool](repeating: false, count: coordinates.count)
        keep[0] = true
        keep[coordinates.count - 1] = true
        recurse(coordinates, 0, coordinates.count - 1, toleranceMeters, &keep)
        return zip(coordinates, keep).compactMap { $1 ? $0 : nil }
    }

    private static func recurse(
        _ points: [Coordinate], _ first: Int, _ last: Int,
        _ tolerance: Double, _ keep: inout [Bool]
    ) {
        guard last > first + 1 else { return }
        var worstIndex = first
        var worstDistance = 0.0

        for index in (first + 1)..<last {
            let distance = perpendicularDistance(
                points[index], from: points[first], to: points[last]
            )
            if distance > worstDistance {
                worstDistance = distance
                worstIndex = index
            }
        }

        guard worstDistance > tolerance else { return }
        keep[worstIndex] = true
        recurse(points, first, worstIndex, tolerance, &keep)
        recurse(points, worstIndex, last, tolerance, &keep)
    }

    /// Distance in metres from `point` to segment `start`–`end`, using an
    /// equirectangular projection. Accurate enough at track scale and far
    /// cheaper than a geodesic computation run millions of times.
    private static func perpendicularDistance(
        _ point: Coordinate, from start: Coordinate, to end: Coordinate
    ) -> Double {
        let metresPerDegree = 111_320.0
        let scale = cos(point.latitude * .pi / 180)

        let px = (point.longitude - start.longitude) * metresPerDegree * scale
        let py = (point.latitude - start.latitude) * metresPerDegree
        let ex = (end.longitude - start.longitude) * metresPerDegree * scale
        let ey = (end.latitude - start.latitude) * metresPerDegree

        let lengthSquared = ex * ex + ey * ey
        guard lengthSquared > 0 else { return (px * px + py * py).squareRoot() }

        let t = max(0, min(1, (px * ex + py * ey) / lengthSquared))
        let dx = px - t * ex
        let dy = py - t * ey
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Evenly thins a series to at most `maxCount` elements, always keeping the
    /// first and last. Used to keep charts responsive on long activities.
    static func downsample<T>(_ values: [T], to maxCount: Int) -> [T] {
        guard maxCount > 2, values.count > maxCount else { return values }
        let stride = Double(values.count - 1) / Double(maxCount - 1)
        var result = [T]()
        result.reserveCapacity(maxCount)
        for step in 0..<maxCount {
            result.append(values[Int((Double(step) * stride).rounded())])
        }
        return result
    }
}
