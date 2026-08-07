import Testing
@testable import Cairn

@Suite("Simplify")
struct SimplifyTests {
    @Test("les extrémités sont toujours préservées")
    func keepsEndpoints() {
        let line = (0..<50).map {
            Coordinate(latitude: 45.0 + Double($0) * 0.001, longitude: 4.0)
        }
        let simplified = Simplify.douglasPeucker(line, toleranceMeters: 15)
        #expect(simplified.first == line.first)
        #expect(simplified.last == line.last)
    }

    @Test("une ligne droite se réduit à deux points")
    func collapsesStraightLine() {
        let line = (0..<100).map {
            Coordinate(latitude: 45.0 + Double($0) * 0.0005, longitude: 4.0)
        }
        #expect(Simplify.douglasPeucker(line, toleranceMeters: 15).count == 2)
    }

    @Test("un détour supérieur à la tolérance est conservé")
    func keepsSignificantDetour() {
        let line = [
            Coordinate(latitude: 45.0, longitude: 4.0),
            Coordinate(latitude: 45.0, longitude: 4.01),
            Coordinate(latitude: 45.0, longitude: 4.02),
        ]
        var withDetour = line
        // ~1 km d'écart, très au-delà de 15 m
        withDetour[1] = Coordinate(latitude: 45.009, longitude: 4.01)
        #expect(Simplify.douglasPeucker(withDetour, toleranceMeters: 15).count == 3)
    }

    @Test("moins de trois points est retourné tel quel")
    func passesThroughShortInput() {
        let two = [
            Coordinate(latitude: 1, longitude: 2), Coordinate(latitude: 3, longitude: 4),
        ]
        #expect(Simplify.douglasPeucker(two) == two)
        #expect(Simplify.douglasPeucker([]).isEmpty)
    }

    @Test("le sous-échantillonnage garde les bornes et respecte le plafond")
    func downsampleKeepsBounds() {
        let values = Array(0..<1000)
        let reduced = Simplify.downsample(values, to: 100)
        #expect(reduced.count <= 100)
        #expect(reduced.first == 0)
        #expect(reduced.last == 999)
    }

    @Test("le sous-échantillonnage ne touche pas une série déjà courte")
    func downsampleShortInput() {
        let values = [1, 2, 3]
        #expect(Simplify.downsample(values, to: 100) == values)
    }

    @Test("le sous-échantillonnage à deux points ne garde que les extrémités")
    func downsampleToTwoKeepsOnlyEndpoints() {
        let values = Array(0..<1000)
        let reduced = Simplify.downsample(values, to: 2)
        #expect(reduced == [0, 999])
    }

    @Test("une trace de points dupliqués se réduit sans boucler")
    func collapsesDuplicatePoints() {
        let point = Coordinate(latitude: 45.75, longitude: 4.83)
        let duplicates = Array(repeating: point, count: 50)
        #expect(Simplify.douglasPeucker(duplicates).count == 2)
    }
}
