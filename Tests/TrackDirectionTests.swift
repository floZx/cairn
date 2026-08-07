import Testing
import MapKit
@testable import StravaLocal

@Suite("TrackDirection")
struct TrackDirectionTests {
    /// A straight run of points heading due east in map space.
    private func eastward(count: Int, spacing: Double = 100) -> [MKMapPoint] {
        (0..<count).map { MKMapPoint(x: Double($0) * spacing, y: 5_000) }
    }

    @Test("une trace vide ou ponctuelle ne produit aucun repère")
    func handlesDegenerateTracks() {
        #expect(TrackDirection.markers(along: [], count: 6).isEmpty)
        #expect(TrackDirection.markers(along: eastward(count: 1), count: 6).isEmpty)
        // Every point identical: no distance travelled, so nothing to point along.
        let stationary = [MKMapPoint](repeating: MKMapPoint(x: 10, y: 10), count: 20)
        #expect(TrackDirection.markers(along: stationary, count: 6).isEmpty)
        #expect(TrackDirection.markers(along: eastward(count: 10), count: 0).isEmpty)
    }

    @Test("le sens suit le trajet, et s'inverse avec lui")
    func pointsAlongTheDirectionOfTravel() {
        let markers = TrackDirection.markers(along: eastward(count: 20), count: 4)
        #expect(markers.count == 4)
        // Due east in map space is an angle of zero; this is the assertion that
        // matters, because an arrow pointing backwards is worse than none.
        #expect(markers.allSatisfy { abs($0.angle) < 0.001 })

        let reversed = TrackDirection.markers(
            along: eastward(count: 20).reversed(), count: 4
        )
        // Due west is π. Same track, opposite direction, opposite arrows.
        #expect(reversed.allSatisfy { abs(abs($0.angle) - .pi) < 0.001 })
    }

    @Test("les repères sont espacés par la distance parcourue, pas par l'indice")
    func spacesByDistanceTravelled() {
        // Dense at the start, sparse afterwards: spacing by index would pile every
        // chevron into the first tenth of the route.
        var points = (0..<50).map { MKMapPoint(x: Double($0), y: 0) }
        points += (1...5).map { MKMapPoint(x: 49 + Double($0) * 1_000, y: 0) }

        let markers = TrackDirection.markers(along: points, count: 5)

        #expect(markers.count == 5)
        let xs = markers.map(\.point.x)
        #expect(xs == xs.sorted())
        // Spread across the whole length rather than clustered near the origin.
        let total = points.last!.x - points.first!.x
        #expect(xs.first! < total * 0.3)
        #expect(xs.last! > total * 0.7)
        // Roughly even gaps, which is the point of measuring by distance.
        let gaps = zip(xs.dropFirst(), xs).map { $0 - $1 }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        #expect(gaps.allSatisfy { abs($0 - mean) < mean * 0.2 })
    }

    @Test("aucun repère ne tombe sur le départ ni sur l'arrivée")
    func keepsClearOfBothEnds() {
        let points = eastward(count: 100)
        let total = points.last!.x - points.first!.x

        let markers = TrackDirection.markers(along: points, count: 8)

        // A chevron on the start would sit under the start marker; one on the end
        // would hang off the line.
        #expect(markers.first!.point.x > total * 0.01)
        #expect(markers.last!.point.x < total * 0.99)
    }

    @Test("un virage à angle droit donne un repère orienté par segment")
    func followsATurn() {
        // East for 1000, then south for 1000.
        var points = (0...10).map { MKMapPoint(x: Double($0) * 100, y: 0) }
        points += (1...10).map { MKMapPoint(x: 1_000, y: Double($0) * 100) }

        let markers = TrackDirection.markers(along: points, count: 2)

        #expect(markers.count == 2)
        // First leg east (0), second leg south — positive y in map space, so +π/2.
        #expect(abs(markers[0].angle) < 0.001)
        #expect(abs(markers[1].angle - .pi / 2) < 0.001)
    }

    @Test("le chevron choisit la couleur qui contraste le plus, pas la plus claire")
    @MainActor
    func picksTheMoreContrastingChevronColor() {
        // Every colour the user can actually pick, rather than examples chosen to
        // agree with me: a previous version of this test used orange, which
        // happened to satisfy a wrong threshold while red — the colour in use —
        // did not, and the chevrons stayed white on a red track.
        for choice in TrackColor.allCases {
            let chosen = DirectedPolylineRenderer.chevronColor(on: choice.nsColor)
            let luminance = DirectedPolylineRenderer.relativeLuminance(
                of: choice.nsColor
            )

            // The contract, computed from the definition rather than restated: of
            // the two candidates, keep the one with the higher WCAG ratio.
            let againstWhite = 1.05 / (luminance + 0.05)
            let againstBlack = (luminance + 0.05) / 0.05
            #expect(chosen == (againstBlack > againstWhite ? .black : .white))
        }

        // And the two cases worth naming outright.
        #expect(DirectedPolylineRenderer.chevronColor(on: .systemRed) == .black)
        #expect(DirectedPolylineRenderer.chevronColor(on: .black) == .white)
    }

    @Test("la luminance est décodée en gamma, pas prise sur les composantes brutes")
    func decodesGamma() {
        let grey = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)

        // Raw components would put mid-grey at 0.5; decoded it sits near 0.21,
        // which is where the eye finds it. Reading it raw is part of how red ended
        // up on the wrong side of the crossover.
        let luminance = DirectedPolylineRenderer.relativeLuminance(of: grey)
        #expect(luminance > 0.18 && luminance < 0.25)

        // Generic Gray, where reading redComponent raises: the conversion has to
        // happen inside, since black is one of the track colours on offer.
        #expect(DirectedPolylineRenderer.relativeLuminance(of: .black) == 0)
        let white = DirectedPolylineRenderer.relativeLuminance(
            of: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        )
        #expect(abs(white - 1) < 0.001)
    }
}
