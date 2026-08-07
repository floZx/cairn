import Testing
import CoreLocation
@testable import Cairn

@Suite("Polyline")
struct PolylineTests {
    @Test("décode le vecteur de référence Google")
    func decodesReferenceVector() {
        let result = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(result.count == 3)
        #expect(abs(result[0].latitude - 38.5) < 0.00001)
        #expect(abs(result[0].longitude - (-120.2)) < 0.00001)
        #expect(abs(result[1].latitude - 40.7) < 0.00001)
        #expect(abs(result[1].longitude - (-120.95)) < 0.00001)
        #expect(abs(result[2].latitude - 43.252) < 0.00001)
        #expect(abs(result[2].longitude - (-126.453)) < 0.00001)
    }

    @Test("une chaîne vide donne un tableau vide")
    func decodesEmpty() {
        #expect(Polyline.decode("").isEmpty)
    }

    @Test("un encodage suivi d'un décodage préserve les coordonnées à 1e-5")
    func roundTrips() {
        let original = [
            Coordinate(latitude: 45.7640, longitude: 4.8357),
            Coordinate(latitude: 45.7650, longitude: 4.8400),
            Coordinate(latitude: 45.7700, longitude: 4.8500),
        ]
        let decoded = Polyline.decode(Polyline.encode(original))
        #expect(decoded.count == original.count)
        for (a, b) in zip(original, decoded) {
            #expect(abs(a.latitude - b.latitude) < 0.00001)
            #expect(abs(a.longitude - b.longitude) < 0.00001)
        }
    }

    @Test("une chaîne tronquée ne plante pas")
    func toleratesTruncatedInput() {
        _ = Polyline.decode("_p~iF~ps|U_ulLnnq")
    }
}
