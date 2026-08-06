import Foundation
import SwiftData

/// One blob per stream, kept out of the row so listing activities never pays
/// for them. Decode with `TrackBlob`: `latlng` as coordinates, `time` as
/// Int32 seconds, everything else as Float scalars.
@Model
final class ActivityStreams {
    var pointCount: Int = 0

    @Attribute(.externalStorage) var latlng: Data?
    @Attribute(.externalStorage) var altitude: Data?
    @Attribute(.externalStorage) var time: Data?
    @Attribute(.externalStorage) var heartrate: Data?
    @Attribute(.externalStorage) var cadence: Data?
    @Attribute(.externalStorage) var watts: Data?
    @Attribute(.externalStorage) var velocitySmooth: Data?
    @Attribute(.externalStorage) var temp: Data?
    @Attribute(.externalStorage) var grade: Data?
    @Attribute(.externalStorage) var moving: Data?

    var activity: Activity?

    init() {}

    var coordinates: [Coordinate] {
        latlng.map(TrackBlob.decodeCoordinates) ?? []
    }
}
