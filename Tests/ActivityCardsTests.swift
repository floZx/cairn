import Testing
import Foundation
import SwiftUI
@testable import Cairn

@Suite("Vignette de trace")
@MainActor
struct TrackThumbnailTests {
    private let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test("la longitude est corrigée par la latitude")
    func longitudeIsScaledByLatitude() {
        // A degree of longitude is only about 70 % of a degree of latitude in
        // France. Plotting both on the same scale stretches every track
        // sideways and turns a round loop into an oval.
        let square = [
            Coordinate(latitude: 45, longitude: 5),
            Coordinate(latitude: 45.01, longitude: 5),
            Coordinate(latitude: 45.01, longitude: 5.01),
            Coordinate(latitude: 45, longitude: 5.01),
        ]
        let points = TrackThumbnail.points(for: square, in: box)
        let width = points.map(\.x).max()! - points.map(\.x).min()!
        let height = points.map(\.y).max()! - points.map(\.y).min()!

        // Equal spans in degrees, so the drawn width must come out *narrower*
        // than the height, by roughly cos(45°).
        #expect(width < height)
        #expect(abs(width / height - cos(45 * .pi / 180)) < 0.02)
    }

    @Test("le tracé tient dans la boîte sans la remplir de force")
    func fitsWithoutStretching() {
        // Squashing a track to fill the box would defeat the purpose: the point
        // of the thumbnail is the shape.
        let line = [
            Coordinate(latitude: 45, longitude: 5),
            Coordinate(latitude: 45.1, longitude: 5.001),
        ]
        let points = TrackThumbnail.points(for: line, in: box.insetBy(dx: 3, dy: 3))

        #expect(points.allSatisfy { box.contains($0) })
        // Very tall and very narrow: it fills the height and stays thin.
        let width = points.map(\.x).max()! - points.map(\.x).min()!
        #expect(width < 5)
    }

    @Test("le nord est en haut")
    func northIsUp() {
        // Latitude grows northwards and y grows downwards, so without the flip
        // every track comes out upside down.
        let points = TrackThumbnail.points(
            for: [
                Coordinate(latitude: 45, longitude: 5),
                Coordinate(latitude: 46, longitude: 5),
            ],
            in: box
        )
        #expect(points[0].y > points[1].y)
    }

    @Test("un tracé absent ou réduit à un point ne dessine rien")
    func degenerateTracksDrawNothing() {
        #expect(TrackThumbnail.points(for: [], in: box).isEmpty)
        #expect(
            TrackThumbnail.points(
                for: [Coordinate(latitude: 45, longitude: 5)], in: box
            ).isEmpty
        )
        // A zero-sized box would divide by zero rather than draw.
        #expect(
            TrackThumbnail.points(
                for: [
                    Coordinate(latitude: 45, longitude: 5),
                    Coordinate(latitude: 46, longitude: 6),
                ],
                in: .zero
            ).isEmpty
        )
    }
}

@Suite("Tri des fiches")
@MainActor
struct ActivitySortTests {
    @Test("le tri des fiches et celui du tableau sont le même")
    func theMenuWritesTheTablesOrder() {
        // Two orders for two presentations of one list would reshuffle
        // everything on each switch.
        let byDistance = ActivitySort.distance.comparators(ascending: false)
        #expect(ActivitySort.current(byDistance) == .distance)
        #expect(ActivitySort.isAscending(byDistance) == false)
    }

    @Test("un ordre posé par une colonne que le menu n'offre pas n'est pas revendiqué")
    func doesNotClaimAnUnknownOrder() {
        // The table sorts by average speed; the menu does not offer it, and must
        // not tick one of its own entries as if it did.
        let bySpeed = [KeyPathComparator(\Activity.averageSpeed, order: .reverse)]
        #expect(ActivitySort.current(bySpeed) == nil)
    }

    @Test("chaque champ démarre dans le sens qu'on attend")
    func eachFieldStartsTheRightWayRound() {
        // A name wants A→Z; a date or a climb want the biggest and the most
        // recent first, because that is the one being looked for.
        #expect(ActivitySort.name.startsAscending)
        #expect(!ActivitySort.date.startsAscending)
        #expect(!ActivitySort.elevation.startsAscending)
    }
}
