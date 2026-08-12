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

@Suite("Les chiffres d'une fiche")
@MainActor
struct ActivityCardFiguresTests {
    private func makeActivity(
        sport: SportType = .run, distance: Double = 9_000,
        movingTime: Int = 2_905, elevation: Double = 32,
        heartrate: Double? = 132
    ) -> Activity {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: sport)
        activity.distance = distance
        activity.movingTime = movingTime
        activity.totalElevationGain = elevation
        activity.averageHeartrate = heartrate
        activity.averageSpeed = movingTime > 0 ? distance / Double(movingTime) : 0
        return activity
    }

    @Test("une course porte ses cinq chiffres, allure comprise")
    func arunCarriesFiveFigures() {
        let figures = ActivityCard.figures(for: makeActivity())
        #expect(figures.count == 5)
        #expect(figures[0].value == Format.distance(9_000))
        #expect(figures[1].value == Format.durationCompact(2_905))
        #expect(figures[2].value == Format.elevation(32))
        #expect(figures[3].value?.contains("/km") == true)
        #expect(figures[4].value == Format.heartrate(132))
    }

    @Test("une séance en salle laisse ses colonnes vides plutôt que des zéros")
    func agymSessionLeavesBlanks() {
        let session = makeActivity(
            sport: .workout, distance: 0, movingTime: 1_560, elevation: 0,
            heartrate: 86
        )
        let figures = ActivityCard.figures(for: session)
        // Les places ne bougent pas : deux lignes voisines restent alignées.
        #expect(figures.count == 5)
        #expect(figures[0].value == nil)
        #expect(figures[1].value == Format.durationCompact(1_560))
        #expect(figures[2].value == nil)
        #expect(figures[3].value == nil)
        #expect(figures[4].value == Format.heartrate(86))
    }

    @Test("sans cardio, la dernière colonne reste vide")
    func nomonitorNoHeartRate() {
        #expect(ActivityCard.figures(for: makeActivity(heartrate: nil))[4].value == nil)
        // Strava envoie zéro sur certaines saisies manuelles : c'est la même
        // absence, et elle ne doit pas laisser un tiret là où on veut du blanc.
        #expect(ActivityCard.figures(for: makeActivity(heartrate: 0))[4].value == nil)
    }

    @Test("l'allure se lit dans l'unité du sport")
    func paceReadsBySport() {
        // La même règle que partout : `Format.speed` décide, pas une seconde.
        let swim = makeActivity(sport: .swim, distance: 1_000, movingTime: 1_500)
        #expect(ActivityCard.figures(for: swim)[3].value?.contains("/100 m") == true)
        let ride = makeActivity(sport: .ride, distance: 32_400, movingTime: 7_200)
        #expect(ActivityCard.figures(for: ride)[3].value?.contains("km/h") == true)
    }

    @Test("une sortie notable se compte en temps ou en distance")
    func notableCountsTimeOrDistance() {
        // 48 minutes de footing : la sortie ordinaire d'une semaine.
        #expect(!ActivityCard.isNotable(makeActivity()))
        // Deux heures de vélo tranquille.
        #expect(
            ActivityCard.isNotable(
                makeActivity(sport: .ride, distance: 15_000, movingTime: 7_200)
            )
        )
        // 25 km de trail, même s'ils allaient vite.
        #expect(
            ActivityCard.isNotable(
                makeActivity(sport: .trailRun, distance: 25_000, movingTime: 5_000)
            )
        )
    }

    @Test("la graisse va au premier chiffre écrit, pas à la première colonne")
    func theleadingFigureIsTheFirstWritten() {
        let trail = makeActivity(sport: .trailRun, distance: 25_700, movingTime: 10_920)
        #expect(ActivityCard.figures(for: trail)[0].isLeading)

        // Une longue séance en salle n'a pas de distance : la graisse tombe
        // sur sa durée, la première chose qu'elle ait à dire.
        let session = makeActivity(
            sport: .workout, distance: 0, movingTime: 6_000, elevation: 0
        )
        let figures = ActivityCard.figures(for: session)
        #expect(!figures[0].isLeading)
        #expect(figures[1].isLeading)
    }

    @Test("une sortie ordinaire ne met la graisse nulle part")
    func anordinaryOutingIsNotEmphasised() {
        #expect(ActivityCard.figures(for: makeActivity()).allSatisfy { !$0.isLeading })
    }
}
