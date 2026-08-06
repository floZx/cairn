import Testing
@testable import StravaLocal

@Suite("BoundingBox")
struct BoundingBoxTests {
    private let lyon = [
        Coordinate(latitude: 45.75, longitude: 4.83),
        Coordinate(latitude: 45.80, longitude: 4.90),
        Coordinate(latitude: 45.70, longitude: 4.85),
    ]

    @Test("englobe tous les points")
    func computesExtent() {
        let box = BoundingBox(coordinates: lyon)
        #expect(box?.minLat == 45.70)
        #expect(box?.maxLat == 45.80)
        #expect(box?.minLon == 4.83)
        #expect(box?.maxLon == 4.90)
    }

    @Test("un tableau vide ne donne pas de boîte")
    func rejectsEmptyInput() {
        #expect(BoundingBox(coordinates: []) == nil)
    }

    @Test("deux boîtes qui se chevauchent s'intersectent")
    func detectsOverlap() {
        let a = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        let b = BoundingBox(minLat: 45.5, maxLat: 47, minLon: 4.5, maxLon: 6)
        #expect(a.intersects(b))
        #expect(b.intersects(a))
    }

    @Test("deux boîtes disjointes ne s'intersectent pas")
    func detectsDisjoint() {
        let a = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        let b = BoundingBox(minLat: 48, maxLat: 49, minLon: 2, maxLon: 3)
        #expect(!a.intersects(b))
    }

    @Test("deux boîtes qui se touchent par un bord s'intersectent")
    func touchingEdgesCount() {
        let a = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        let b = BoundingBox(minLat: 46, maxLat: 47, minLon: 4, maxLon: 5)
        #expect(a.intersects(b))
    }

    @Test("l'appartenance d'un point est testée bord inclus")
    func containsPoint() {
        let box = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        #expect(box.contains(Coordinate(latitude: 45.5, longitude: 4.5)))
        #expect(box.contains(Coordinate(latitude: 45, longitude: 4)))
        #expect(!box.contains(Coordinate(latitude: 44.9, longitude: 4.5)))
    }

    @Test("containsAnyPoint distingue une trace qui traverse d'une trace hors zone")
    func containsAnyPointOfTrack() {
        let box = BoundingBox(minLat: 45.79, maxLat: 45.81, minLon: 4.89, maxLon: 4.91)
        #expect(box.containsAnyPoint(of: lyon))
        let elsewhere = [Coordinate(latitude: 48.85, longitude: 2.35)]
        #expect(!box.containsAnyPoint(of: elsewhere))
    }

    @Test("la boîte monde contient n'importe quoi")
    func worldContainsEverything() {
        #expect(BoundingBox.world.contains(Coordinate(latitude: -33.87, longitude: 151.2)))
    }
}
