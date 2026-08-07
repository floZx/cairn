import Testing
@testable import Cairn

@Suite("DistanceAxis")
struct DistanceAxisTests {
    @Test("une trace vide ou d'un seul point n'a pas d'axe")
    func handlesShortInput() {
        #expect(DistanceAxis.cumulativeMetres(along: []).isEmpty)
        #expect(
            DistanceAxis.cumulativeMetres(
                along: [Coordinate(latitude: 45.75, longitude: 4.83)]
            ) == [0]
        )
    }

    @Test("le premier point est à zéro et la distance croît")
    func startsAtZeroAndGrows() {
        let track = (0..<5).map {
            Coordinate(latitude: 45.75 + Double($0) * 0.001, longitude: 4.83)
        }
        let distances = DistanceAxis.cumulativeMetres(along: track)

        #expect(distances.count == track.count)
        #expect(distances[0] == 0)
        for index in 1..<distances.count {
            #expect(distances[index] > distances[index - 1])
        }
    }

    @Test("un degré de latitude fait environ 111 km")
    func matchesKnownDistance() {
        let track = [
            Coordinate(latitude: 45.0, longitude: 4.0),
            Coordinate(latitude: 46.0, longitude: 4.0),
        ]
        let total = DistanceAxis.cumulativeMetres(along: track).last!
        // 111,2 km à ±1 %.
        #expect(abs(total - 111_200) / 111_200 < 0.01)
    }

    @Test("la longitude se resserre avec la latitude")
    func longitudeShrinksWithLatitude() {
        let atEquator = DistanceAxis.cumulativeMetres(along: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
        ]).last!
        let atLyon = DistanceAxis.cumulativeMetres(along: [
            Coordinate(latitude: 45.75, longitude: 4),
            Coordinate(latitude: 45.75, longitude: 5),
        ]).last!

        // cos(45,75°) ≈ 0,698 : un degré de longitude y est bien plus court.
        #expect(atLyon < atEquator)
        #expect(abs(atLyon / atEquator - 0.698) < 0.02)
    }

    @Test("l'index le plus proche d'une distance est retrouvé")
    func findsNearestIndex() {
        let distances = [0.0, 100, 200, 300, 400]

        #expect(DistanceAxis.nearestIndex(to: 0, in: distances) == 0)
        #expect(DistanceAxis.nearestIndex(to: 210, in: distances) == 2)
        #expect(DistanceAxis.nearestIndex(to: 260, in: distances) == 3)
        #expect(DistanceAxis.nearestIndex(to: 10_000, in: distances) == 4)
        #expect(DistanceAxis.nearestIndex(to: -50, in: distances) == 0)
        #expect(DistanceAxis.nearestIndex(to: 100, in: []) == nil)
    }
}
