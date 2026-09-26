import Testing
import Foundation
@testable import Cairn

@Suite("Titres : lecture des tours")
struct IntervalReaderTests {
    private func lap(
        _ metres: Double, _ seconds: Int, hr: Double? = nil, climb: Double = 0
    ) -> LapFigures {
        LapFigures(distance: metres, movingTime: seconds, averageHeartrate: hr, elevationGain: climb)
    }

    /// « Seuil 3x12´ », tel que la montre l'a découpé : un tour automatique à
    /// chaque kilomètre, y compris pendant les efforts.
    @Test("un seuil coupé au kilomètre se recolle en Seuil 3×12′/2′")
    func readsRealThreshold() {
        let laps = [
            lap(1000, 362), lap(1000, 339), lap(228, 75),
            lap(1000, 254), lap(1000, 260), lap(787, 205), lap(328, 120),
            lap(1000, 259), lap(1000, 265), lap(729, 194), lap(309, 120),
            lap(1000, 260), lap(1000, 268), lap(706, 190),
            lap(1000, 367), lap(634, 196),
        ]
        #expect(IntervalReader.read(laps) == "Seuil 3×12′/2′")
    }

    /// « 4x6′ » : les récupérations marchées sont si lentes que le meilleur
    /// seuil unique tombait entre marche et course.
    @Test("des récupérations marchées ne collent pas l'échauffement au premier effort")
    func walkedRecoveries() {
        let laps = [
            lap(1000, 377), lap(1000, 326), lap(231, 74),
            lap(1000, 249), lap(425, 110), lap(141, 120),
            lap(1000, 254), lap(407, 105), lap(175, 120),
            lap(1000, 255), lap(407, 104), lap(124, 120),
            lap(1000, 258), lap(393, 101),
            lap(1000, 347), lap(1000, 340), lap(268, 83),
        ]
        #expect(IntervalReader.read(laps) == "Seuil 4×6′/2′")
    }

    @Test("des 400 m se lisent en distance, avec la récup")
    func readsTrackReps() {
        var laps = [lap(2_000, 720)]
        // Cut at the metre by the watch, run a second or two apart.
        for time in [86, 88, 87, 90, 89, 88, 91, 87, 89, 90] { laps += [lap(400, time), lap(200, 75)] }
        laps.append(lap(1_500, 540))
        #expect(IntervalReader.read(laps) == "10×400 m/1′15")
    }

    @Test("un trail coupé au kilomètre n'est pas un fractionné, même avec des descentes")
    func autoLapTrailIsNotIntervals() {
        let laps = [390, 420, 300, 510, 280, 450, 330, 600, 290, 410].map { lap(1_000, $0) } + [lap(420, 150)]
        #expect(IntervalReader.read(laps) == nil)
    }

    @Test("sans distance, c'est la fréquence cardiaque qui distingue l'effort")
    func readsByHeartRate() {
        let laps = [
            lap(0, 300, hr: 100),
            lap(0, 240, hr: 150), lap(0, 60, hr: 110),
            lap(0, 240, hr: 152), lap(0, 60, hr: 112),
            lap(0, 242, hr: 155), lap(0, 300, hr: 105),
        ]
        #expect(IntervalReader.read(laps) == "Seuil 3×4′/1′")
    }

    /// « Côtes 8x45″ » : 19 m de montée pour 148 m pendant les efforts.
    @Test("des efforts qui grimpent sont des côtes")
    func readsHills() {
        var laps = [lap(1000, 343), lap(1000, 345, climb: 6.8), lap(273, 121)]
        for recovery in [86, 92, 118, 108, 116, 96, 132] {
            laps += [lap(148, 45, climb: 19), lap(165, recovery, climb: 0.6)]
        }
        laps += [lap(143, 45, climb: 18.4), lap(1000, 564), lap(687, 285)]
        #expect(IntervalReader.read(laps) == "Côtes 8×45″")
    }

    @Test("des efforts courts ne sont que leur format")
    func shortRepsAreJustTheFormat() {
        var laps = [lap(2000, 700)]
        for _ in 0..<12 { laps += [lap(130, 30), lap(80, 30)] }
        laps.append(lap(1500, 540))
        #expect(IntervalReader.read(laps) == "12×30″/30″")
    }

    @Test("deux accélérations ne font pas une séance")
    func twoEffortsAreNotASession() {
        let laps = [lap(2_000, 700), lap(800, 200), lap(1_500, 540), lap(800, 200), lap(2_000, 700)]
        #expect(IntervalReader.read(laps) == nil)
    }

    @Test("un seul tour ne dit rien")
    func singleLap() {
        #expect(IntervalReader.read([lap(10_000, 3_000)]) == nil)
    }
}

@Suite("Titres : ingrédients")
struct TitleIngredientsTests {
    /// A straight line north from Sury-le-Comtal, `n` points, `step` degrees apart.
    private func line(_ n: Int, step: Double = 0.001) -> [Coordinate] {
        (0..<n).map { Coordinate(latitude: 45.537 + Double($0) * step, longitude: 4.186) }
    }

    @Test("une boucle, un aller-retour, un trajet")
    func shapes() {
        let out = line(40)
        #expect(TitleIngredients.shape(of: out) == .pointToPoint)
        #expect(TitleIngredients.shape(of: out + out.reversed()) == .outAndBack)

        let loop = (0..<60).map { i -> Coordinate in
            let angle = Double(i) / 59 * 2 * .pi
            return Coordinate(
                latitude: 45.537 + 0.02 * sin(angle), longitude: 4.186 + 0.02 * (1 - cos(angle))
            )
        }
        #expect(TitleIngredients.shape(of: loop) == .loop)
        #expect(TitleIngredients.shape(of: line(3)) == nil)
    }

    @Test("le relief se juge selon le sport")
    func reliefBySport() {
        #expect(TitleIngredients.relief(elevation: 180, distanceKm: 32, sport: .ride) == .flat)
        #expect(TitleIngredients.relief(elevation: 300, distanceKm: 32, sport: .ride) == .rolling)
        #expect(TitleIngredients.relief(elevation: 300, distanceKm: 10, sport: .trailRun) == .hilly)
        #expect(TitleIngredients.relief(elevation: 50, distanceKm: 10, sport: .run) == .flat)
        #expect(TitleIngredients.relief(elevation: 0, distanceKm: 0, sport: .workout) == nil)
    }

    @Test("plus longue ou plus courte que d'habitude")
    func lengthAgainstUsual() {
        #expect(TitleIngredients.length(distanceKm: 21, usualKm: 10) == .long)
        #expect(TitleIngredients.length(distanceKm: 5, usualKm: 10) == .short)
        #expect(TitleIngredients.length(distanceKm: 11, usualKm: 10) == .usual)
        #expect(TitleIngredients.length(distanceKm: 11, usualKm: nil) == nil)
    }

    @Test("le point le plus éloigné fait partie des points géocodés")
    func samplesIncludeFarthest() {
        let track = line(50) + line(50).reversed()
        let points = TitleIngredients.samplePoints(of: track)
        #expect(points.first == track.first)
        #expect(points.contains(track[49]))
        #expect(points.count <= 7)
    }
}

@Suite("Titres : propositions")
struct TitleSuggestionsTests {
    private func ride() -> TitleIngredients {
        var i = TitleIngredients(
            sport: .ride, weekday: "mercredi", partOfDay: .evening,
            distanceKm: 32.4, movingMinutes: 75, elevationGain: 180,
            relief: .flat, shape: .loop, length: .usual
        )
        i.places = ["Sury-le-Comtal", "L'Hôpital-le-Grand", "Précieux"]
        return i
    }

    @Test("une boucle à vélo se nomme par la commune du bout, le moment et les chiffres")
    func rideLoop() {
        let titles = TitleSuggestions.make(ride())
        #expect(titles == [
            "Boucle par Précieux",
            "Vélo vers Précieux",
            "Sury-le-Comtal / Précieux",
            "Vélo du mercredi soir",
            "32 km et 180 m D+ par Précieux",
        ])
    }

    @Test("le relief s'accorde avec le sport")
    func reliefAgrees() {
        var run = ride()
        run.sport = .run
        run.relief = .rolling
        let titles = TitleSuggestions.make(run)
        #expect(titles.contains("Boucle vallonnée par Précieux"))
        #expect(titles.contains("Course vallonnée vers Précieux"))

        var trail = run
        trail.sport = .trailRun
        #expect(TitleSuggestions.make(trail).contains("Trail vallonné vers Précieux"))
    }

    @Test("la séance lue dans les tours passe en tête")
    func sessionFirst() {
        var i = ride()
        i.sport = .run
        i.places = ["Sury-le-Comtal"]
        i.intervals = "Seuil 3×12′/2′"
        let titles = TitleSuggestions.make(i)
        #expect(titles.first == "Seuil 3×12′/2′")
        #expect(titles[1] == "Seuil 3×12′/2′ à Sury-le-Comtal")
    }

    @Test("parcours habituel, sortie longue, aller-retour, trajet")
    func wayVariants() {
        var i = ride()
        i.previousOnRoute = 4
        i.length = .long
        let titles = TitleSuggestions.make(i)
        #expect(titles.prefix(2) == ["La boucle habituelle par Précieux", "Grande boucle par Précieux"])

        i.shape = .outAndBack
        #expect(TitleSuggestions.make(i).contains("Aller-retour à Précieux"))
        i.shape = .pointToPoint
        #expect(TitleSuggestions.make(i).contains("Sury-le-Comtal → Précieux"))
    }

    @Test("home-trainer, vélotaf et renfo sans distance")
    func indoorCommuteWorkout() {
        var trainer = ride()
        trainer.isIndoor = true
        trainer.places = []
        #expect(TitleSuggestions.make(trainer).first == "Home-trainer du mercredi soir")

        var commute = ride()
        commute.isCommute = true
        #expect(TitleSuggestions.make(commute).first == "Vélotaf du mercredi soir")

        let gym = TitleIngredients(
            sport: .workout, weekday: "jeudi", partOfDay: .evening,
            distanceKm: 0, movingMinutes: 45, elevationGain: 0
        )
        #expect(TitleSuggestions.make(gym) == ["Renfo du jeudi soir", "Renfo · 45 min"])
    }

    @Test("une course sous 145 de moyenne se propose en Footing et en EF")
    func easyRun() {
        var run = ride()
        run.sport = .run
        run.places = ["Sury-le-Comtal", "Bonson"]
        run.averageHeartrate = 138
        let titles = TitleSuggestions.make(run)
        #expect(titles.prefix(2) == ["Footing Sury-le-Comtal / Bonson", "EF Sury-le-Comtal / Bonson"])

        run.places = ["Sury-le-Comtal"]
        #expect(TitleSuggestions.make(run).prefix(2) == ["Footing à Sury-le-Comtal", "EF Sury-le-Comtal"])

        run.averageHeartrate = 146
        #expect(!TitleSuggestions.make(run).contains { $0.hasPrefix("Footing") })

        run.averageHeartrate = 138
        run.intervals = "12×30″/30″"
        #expect(!TitleSuggestions.make(run).contains { $0.hasPrefix("EF") })

        var bike = ride()
        bike.averageHeartrate = 120
        #expect(!TitleSuggestions.make(bike).contains { $0.hasPrefix("Footing") })
    }

    @Test("les titres automatiques sont banals, pas ceux qu'on a écrits")
    func banalTitles() {
        for name in [
            "Course à pied le matin", "Entraînement aux poids dans l'après-midi", "Morning Ride",
            "Afternoon Weight Training", "Course à pied (tapis)", "Sortie en vélo électrique en soirée",
            "Lyon Course à pied", "Renforcement fonctionnel", "",
        ] {
            #expect(TitleSuggestions.isBanal(name), "\(name)")
        }
        for name in [
            "Seuil 3x12´", "Sury-le-Comtal", "Sury-le-Comtal / Bonson", "EF Sury-le-Comtal / Bonson",
            "Battue citoyenne", "Vélotaf", "Haut du corps", "Footing avec le fiston",
        ] {
            #expect(!TitleSuggestions.isBanal(name), "\(name)")
        }
    }

    @Test("le titre actuel n'est pas reproposé")
    func avoidsCurrent() {
        #expect(!TitleSuggestions.make(ride(), avoiding: "boucle par précieux").contains("Boucle par Précieux"))
    }
}
