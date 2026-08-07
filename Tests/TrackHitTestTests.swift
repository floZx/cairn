import Testing
import MapKit
@testable import Cairn

@Suite("TrackHitTest")
struct TrackHitTestTests {
    /// A straight segment from (0, 0) to (1000, 0) in map space.
    private let straight = [MKMapPoint(x: 0, y: 0), MKMapPoint(x: 1_000, y: 0)]

    @Test("la distance se mesure au segment, pas à ses extrémités")
    func measuresToTheSegment() {
        // Halfway along, ten units off: an endpoint-only distance would report
        // about 500 and miss every click on a long straight — which is most of a
        // simplified track's length.
        let middle = MKMapPoint(x: 500, y: 10)
        #expect(
            abs(TrackHitTest.distance(from: middle, to: straight[0], straight[1]) - 10)
                < 0.001
        )

        // Past the end, the nearest point is the end itself.
        let beyond = MKMapPoint(x: 1_030, y: 0)
        #expect(
            abs(TrackHitTest.distance(from: beyond, to: straight[0], straight[1]) - 30)
                < 0.001
        )

        // A zero-length segment falls back to the point, rather than dividing by
        // zero: a track can repeat a coordinate.
        let degenerate = MKMapPoint(x: 3, y: 4)
        #expect(
            abs(
                TrackHitTest.distance(
                    from: degenerate, to: MKMapPoint(x: 0, y: 0), MKMapPoint(x: 0, y: 0)
                ) - 5
            ) < 0.001
        )
    }

    @Test("un clic hors tolérance ne sélectionne rien")
    func missesWhenTooFar() {
        let click = MKMapPoint(x: 500, y: 50)

        #expect(TrackHitTest.nearestTrack(to: click, in: [straight], within: 20) == nil)
        #expect(TrackHitTest.nearestTrack(to: click, in: [straight], within: 60) == 0)
        // Nothing on screen, nothing to pick.
        #expect(TrackHitTest.nearestTrack(to: click, in: [], within: 60) == nil)
        // A single point is not a track: there is no segment to be near.
        #expect(
            TrackHitTest.nearestTrack(
                to: click, in: [[MKMapPoint(x: 500, y: 50)]], within: 60
            ) == nil
        )
    }

    @Test("entre deux traces proches, la plus proche gagne")
    func picksTheNearestOfSeveral() {
        let near = [MKMapPoint(x: 0, y: 12), MKMapPoint(x: 1_000, y: 12)]
        let far = [MKMapPoint(x: 0, y: 40), MKMapPoint(x: 1_000, y: 40)]
        let click = MKMapPoint(x: 500, y: 0)

        // Both are within tolerance, so this is the assertion that matters:
        // opening the wrong activity is worse than opening none.
        #expect(TrackHitTest.nearestTrack(to: click, in: [far, near], within: 60) == 1)
        #expect(TrackHitTest.nearestTrack(to: click, in: [near, far], within: 60) == 0)
    }

    @Test("une trace dont la boîte est loin est écartée sans examiner ses segments")
    func skipsDistantTracks() {
        // The rectangle test is what keeps a click cheap with hundreds of tracks
        // on screen. Here it also has to be *correct*: a track whose box is far
        // must not be picked however many points it has.
        let distant = (0..<500).map { MKMapPoint(x: Double($0), y: 100_000) }
        let click = MKMapPoint(x: 250, y: 0)

        #expect(
            TrackHitTest.nearestTrack(to: click, in: [distant], within: 50) == nil
        )
        // And a track whose box is far in x, not y — both axes are checked.
        let sideways = [MKMapPoint(x: 90_000, y: 0), MKMapPoint(x: 91_000, y: 0)]
        #expect(
            TrackHitTest.nearestTrack(to: click, in: [sideways], within: 50) == nil
        )
    }

    @Test("un clic sur un virage trouve bien la trace")
    func findsATrackAtACorner() {
        // A right angle: the click sits inside the elbow, near neither midpoint
        // but close to both segments.
        let corner = [
            MKMapPoint(x: 0, y: 0),
            MKMapPoint(x: 1_000, y: 0),
            MKMapPoint(x: 1_000, y: 1_000),
        ]
        let click = MKMapPoint(x: 995, y: 5)

        #expect(TrackHitTest.nearestTrack(to: click, in: [corner], within: 10) == 0)
    }
}
