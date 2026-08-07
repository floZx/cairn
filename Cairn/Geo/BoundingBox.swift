import Foundation

/// An axis-aligned lat/lon extent. Stored on `Activity` as four indexed columns
/// so the database can pre-filter a geographic query without touching tracks.
struct BoundingBox: Sendable, Equatable {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    init?(coordinates: [Coordinate]) {
        guard let first = coordinates.first else { return nil }
        var box = BoundingBox(
            minLat: first.latitude, maxLat: first.latitude,
            minLon: first.longitude, maxLon: first.longitude
        )
        for coordinate in coordinates.dropFirst() {
            box.minLat = min(box.minLat, coordinate.latitude)
            box.maxLat = max(box.maxLat, coordinate.latitude)
            box.minLon = min(box.minLon, coordinate.longitude)
            box.maxLon = max(box.maxLon, coordinate.longitude)
        }
        self = box
    }

    static let world = BoundingBox(
        minLat: -90, maxLat: 90, minLon: -180, maxLon: 180
    )

    func intersects(_ other: BoundingBox) -> Bool {
        minLat <= other.maxLat && maxLat >= other.minLat
            && minLon <= other.maxLon && maxLon >= other.minLon
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= minLat && coordinate.latitude <= maxLat
            && coordinate.longitude >= minLon && coordinate.longitude <= maxLon
    }

    func containsAnyPoint(of coordinates: [Coordinate]) -> Bool {
        coordinates.contains(where: contains)
    }
}
