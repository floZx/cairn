import CoreLocation

/// A latitude/longitude pair. Deliberately independent of CoreLocation so the
/// Geo layer stays testable and Sendable.
struct Coordinate: Sendable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ cl: CLLocationCoordinate2D) {
        self.init(latitude: cl.latitude, longitude: cl.longitude)
    }

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
