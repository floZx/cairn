import Testing
@testable import Cairn

@Suite("TrackDensity")
struct TrackDensityTests {
    /// A tight cluster of 40 points around Lyon.
    private var lyonCluster: [Coordinate] {
        (0..<40).map {
            Coordinate(
                latitude: 45.75 + Double($0) * 0.0005,
                longitude: 4.83 + Double($0) * 0.0005
            )
        }
    }

    @Test("aucune trace ne donne aucune région")
    func noTracksNoRegion() {
        #expect(TrackDensity.focusRegion(for: []) == nil)
        #expect(TrackDensity.focusRegion(for: [[]]) == nil)
    }

    @Test("une sortie isolée à l'étranger n'élargit pas le cadrage")
    func ignoresDistantOutlier() {
        let sydney = [Coordinate(latitude: -33.8688, longitude: 151.2093)]
        let box = TrackDensity.focusRegion(for: [lyonCluster, sydney])

        #expect(box != nil)
        // The region stays on Lyon and does not stretch to the antipodes.
        #expect(box!.contains(Coordinate(latitude: 45.75, longitude: 4.83)))
        #expect(!box!.contains(sydney[0]))
        #expect(box!.maxLat - box!.minLat < 1)
    }

    @Test("entre deux zones, la plus fréquentée gagne")
    func picksTheBusierCluster() {
        // Paris gets three points, Lyon forty.
        let paris = (0..<3).map {
            Coordinate(latitude: 48.85 + Double($0) * 0.001, longitude: 2.35)
        }
        let box = TrackDensity.focusRegion(for: [lyonCluster, paris])

        #expect(box != nil)
        #expect(box!.contains(Coordinate(latitude: 45.75, longitude: 4.83)))
        #expect(!box!.contains(paris[0]))
    }

    @Test("un point unique produit une région d'étendue minimale, pas un point")
    func singlePointGetsMinimumSpan() {
        let box = TrackDensity.focusRegion(
            for: [[Coordinate(latitude: 45.75, longitude: 4.83)]]
        )

        #expect(box != nil)
        // Compared with a tolerance on purpose: padding a single latitude by
        // half the span and subtracting the two results back is not exact in
        // binary floating point (45.76 - 45.74 == 0.019999999999996), and the
        // contract here is "wide enough to be usable", not an exact width.
        let epsilon = 1e-9
        #expect(box!.maxLat - box!.minLat >= TrackDensity.minimumSpanDegrees - epsilon)
        #expect(box!.maxLon - box!.minLon >= TrackDensity.minimumSpanDegrees - epsilon)
        #expect(box!.contains(Coordinate(latitude: 45.75, longitude: 4.83)))
    }

    @Test("une zone unique est cadrée sur l'ensemble de ses points")
    func singleClusterCoversAllOfIt() {
        let box = TrackDensity.focusRegion(for: [lyonCluster])

        #expect(box != nil)
        for point in lyonCluster {
            #expect(box!.contains(point))
        }
    }

    @Test("le résultat ne dépend pas de l'ordre des traces")
    func isOrderIndependent() {
        let paris = (0..<3).map {
            Coordinate(latitude: 48.85 + Double($0) * 0.001, longitude: 2.35)
        }
        let a = TrackDensity.focusRegion(for: [lyonCluster, paris])
        let b = TrackDensity.focusRegion(for: [paris, lyonCluster])
        #expect(a == b)
    }
}
