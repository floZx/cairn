import Testing
import Foundation
@testable import StravaLocal

@Suite("TrackBlob")
struct TrackBlobTests {
    @Test("les coordonnées font un aller-retour exact")
    func coordinatesRoundTrip() {
        let coordinates = [
            Coordinate(latitude: 45.764043, longitude: 4.835659),
            Coordinate(latitude: -33.868820, longitude: 151.209290),
            Coordinate(latitude: 0, longitude: 0),
        ]
        let decoded = TrackBlob.decodeCoordinates(TrackBlob.encode(coordinates: coordinates))
        #expect(decoded == coordinates)
    }

    @Test("un blob de coordonnées fait 16 octets par point")
    func coordinateBlobIsCompact() {
        let coordinates = Array(
            repeating: Coordinate(latitude: 1, longitude: 2), count: 100
        )
        #expect(TrackBlob.encode(coordinates: coordinates).count == 1600)
    }

    @Test("les scalaires font un aller-retour exact")
    func scalarsRoundTrip() {
        let values: [Float] = [0, 1.5, -20.25, 1234.5]
        #expect(TrackBlob.decodeScalars(TrackBlob.encode(scalars: values)) == values)
    }

    @Test("les temps font un aller-retour exact")
    func timesRoundTrip() {
        let values: [Int32] = [0, 1, 60, 3600, 86_399]
        #expect(TrackBlob.decodeTimes(TrackBlob.encode(times: values)) == values)
    }

    @Test("un blob vide donne un tableau vide")
    func emptyBlob() {
        #expect(TrackBlob.decodeCoordinates(Data()).isEmpty)
        #expect(TrackBlob.decodeScalars(Data()).isEmpty)
    }

    @Test("un blob de taille non multiple ignore la queue incomplète")
    func truncatedBlobIsTolerated() {
        var data = TrackBlob.encode(coordinates: [Coordinate(latitude: 1, longitude: 2)])
        data.append(contentsOf: [0x01, 0x02, 0x03])
        #expect(TrackBlob.decodeCoordinates(data).count == 1)
    }
}
