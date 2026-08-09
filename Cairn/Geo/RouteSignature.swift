import Foundation

/// Decides whether two recorded tracks are the same course — Strava's
/// « matched activities », for comparing efforts over the years.
///
/// Both tracks are resampled to the same number of points, evenly spaced
/// along their own length; the mean point-to-point distance between the two
/// samplings is then the figure of merit. Comparing by position *along the
/// path* makes direction matter for free: a loop ridden the other way pairs
/// its kilometre 2 with the other's kilometre 38 and fails, while an
/// out-and-back — symmetric by nature — matches in both directions, which is
/// exactly what "same course" means for one.
enum RouteSignature {
    /// Enough to pin a course's shape, few enough that comparing one activity
    /// against hundreds stays free.
    static let sampleCount = 32

    /// GPS drift between two honest recordings of the same road is tens of
    /// metres; parallel streets are a hundred or more. The floor covers short
    /// outings, the percentage lets long ones breathe (a 100 km course taking
    /// one different roundabout is still the same course), the cap keeps
    /// « breathe » from meaning « a valley away ».
    static func tolerance(forDistance distance: Double) -> Double {
        min(max(75, distance * 0.01), 250)
    }

    /// The track resampled to `sampleCount` points, evenly spaced along its
    /// cumulative length. nil when there is no track to speak of.
    static func signature(of coordinates: [Coordinate]) -> [Coordinate]? {
        guard coordinates.count > 1 else { return nil }
        let steps = zip(coordinates, coordinates.dropFirst()).map { $0.distance(to: $1) }
        let total = steps.reduce(0, +)
        guard total > 0 else { return nil }

        var samples: [Coordinate] = [coordinates[0]]
        samples.reserveCapacity(sampleCount)
        var covered = 0.0        // length of fully consumed segments
        var segment = 0          // index into `steps`
        for index in 1..<sampleCount {
            let target = total * Double(index) / Double(sampleCount - 1)
            while segment < steps.count - 1, covered + steps[segment] < target {
                covered += steps[segment]
                segment += 1
            }
            let step = steps[segment]
            let fraction = step > 0 ? min(1, (target - covered) / step) : 1
            let from = coordinates[segment]
            let to = coordinates[segment + 1]
            samples.append(Coordinate(
                latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                longitude: from.longitude + (to.longitude - from.longitude) * fraction
            ))
        }
        return samples
    }

    /// Mean distance between paired sample points, in metres.
    static func meanDeviation(_ a: [Coordinate], _ b: [Coordinate]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        return zip(a, b).reduce(0) { $0 + $1.0.distance(to: $1.1) } / Double(a.count)
    }

    /// Same course? Lengths within 10 % of the longer, shapes within
    /// tolerance of each other.
    static func matches(
        _ a: [Coordinate], _ b: [Coordinate],
        distanceA: Double, distanceB: Double
    ) -> Bool {
        let longer = max(distanceA, distanceB)
        guard longer > 0, abs(distanceA - distanceB) <= longer * 0.10 else {
            return false
        }
        return meanDeviation(a, b) <= tolerance(forDistance: longer)
    }
}
