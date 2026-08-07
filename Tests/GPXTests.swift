import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("GPX")
@MainActor
struct GPXTests {
    /// Roughly a kilometre of coastline near Marseille, climbing 50 m.
    private func sampleGPX(
        name: String = "Sortie du matin", type: String = "running"
    ) -> Data {
        var points = ""
        for index in 0..<11 {
            let latitude = 43.2900 + Double(index) * 0.0009
            let time = "2026-03-14T07:0\(index % 10):00Z"
            points += """
                  <trkpt lat="\(latitude)" lon="5.3700">
                    <ele>\(100 + index * 5)</ele>
                    <time>\(time)</time>
                  </trkpt>

            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(name)</name>
            <type>\(type)</type>
            <trkseg>
        \(points)    </trkseg>
          </trk>
        </gpx>
        """.data(using: .utf8)!
    }

    // MARK: - Lecture

    @Test("un GPX ordinaire donne ses points, son nom et son type")
    func parsesAPlainFile() throws {
        let track = try GPXParser.parse(data: sampleGPX())

        #expect(track.name == "Sortie du matin")
        #expect(track.type == "running")
        #expect(track.points.count == 11)
        #expect(track.points[0].coordinate.latitude == 43.29)
        #expect(track.points[0].elevation == 100)
        #expect(track.points[0].time != nil)
    }

    @Test("un tracé sans altitude ni horodatage reste lisible")
    func parsesABareRoute() throws {
        // A route drawn on a map, not a recording. Refusing it would refuse a
        // whole category of files people legitimately have.
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <rte>
            <name>Boucle du plateau</name>
            <rtept lat="45.10" lon="5.70"/>
            <rtept lat="45.11" lon="5.71"/>
          </rte>
        </gpx>
        """.data(using: .utf8)!

        let track = try GPXParser.parse(data: data)
        #expect(track.name == "Boucle du plateau")
        #expect(track.points.count == 2)
        #expect(track.points[0].elevation == nil)
        #expect(track.points[0].time == nil)
    }

    @Test("le nom du fichier sert de repli quand le tracé n'en porte pas")
    func fallsBackToTheMetadataNameThenTheFileName() throws {
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>Depuis les métadonnées</name></metadata>
          <wpt lat="1" lon="1"><name>Un point de passage</name></wpt>
          <trk><trkseg><trkpt lat="45.10" lon="5.70"/></trkseg></trk>
        </gpx>
        """.data(using: .utf8)!

        // The waypoint's name must not be mistaken for the track's — it is the
        // one `<name>` in the file that names something else entirely.
        #expect(try GPXParser.parse(data: data).name == "Depuis les métadonnées")
    }

    @Test("un fichier illisible ou vide est refusé explicitement")
    func rejectsUnusableFiles() {
        #expect(throws: GPXError.self) {
            try GPXParser.parse(data: Data("pas du XML".utf8))
        }
        let empty = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><trkseg/></trk></gpx>
        """.data(using: .utf8)!
        #expect(throws: GPXError.self) { try GPXParser.parse(data: empty) }
    }

    @Test("les horodatages avec et sans fraction de seconde sont acceptés")
    func readsBothTimestampShapes() {
        // Garmin writes one shape, Strava the other; a file from either has to
        // keep its times, or the moving time silently becomes the elapsed one.
        #expect(GPXParser.date(from: "2026-03-14T07:00:00Z") != nil)
        #expect(GPXParser.date(from: "2026-03-14T07:00:00.000Z") != nil)
        #expect(GPXParser.date(from: "pas une date") == nil)
    }

    // MARK: - Mesures

    @Test("le bruit d'altitude ne devient pas du dénivelé")
    func ignoresElevationNoise() {
        // A flat ride whose barometer wanders by a metre. Summing every positive
        // delta would report 5 m of climbing on ground that never rose.
        let jitter: [Double] = [100, 101, 100, 101, 100, 101, 100]
        #expect(TrackMetrics.elevationGain(of: jitter) == 0)

        // A real climb made of one-metre steps must still count, which is what
        // rules out the naive fix of dropping every delta under the floor —
        // that would report zero here. Hysteresis leaves at most one threshold
        // uncounted at the top, hence the range rather than an exact 100.
        let climb = (0...100).map { 100 + Double($0) }
        let gain = TrackMetrics.elevationGain(of: climb)
        #expect(gain > 100 - TrackMetrics.elevationNoiseFloor && gain <= 100)
    }

    @Test("le temps à l'arrêt ne compte pas dans le temps en mouvement")
    func excludesStops() {
        let moving = Coordinate(latitude: 45, longitude: 5)
        let next = Coordinate(latitude: 45.001, longitude: 5)
        let start = Date(timeIntervalSince1970: 0)
        // Three intervals of 10 s: move, stand still, move.
        let coordinates = [moving, next, next, Coordinate(latitude: 45.002, longitude: 5)]
        let times = (0..<4).map { start.addingTimeInterval(Double($0) * 10) }

        #expect(TrackMetrics.elapsedTime(times) == 30)
        #expect(TrackMetrics.movingTime(coordinates: coordinates, times: times) == 20)
    }

    @Test("sans horodatage exploitable, le temps total est rendu tel quel")
    func fallsBackToElapsed() {
        // Better an honest total than a moving time computed from series that
        // do not line up.
        let coordinates = [Coordinate(latitude: 45, longitude: 5)]
        let times = (0..<3).map { Date(timeIntervalSince1970: Double($0) * 10) }
        #expect(TrackMetrics.movingTime(coordinates: coordinates, times: times) == 20)
    }

    @Test("la distance suit la Terre, pas un plan")
    func measuresGeodesicDistance() {
        // One degree of latitude is about 111 km everywhere.
        let metres = Coordinate(latitude: 45, longitude: 5)
            .distance(to: Coordinate(latitude: 46, longitude: 5))
        #expect(abs(metres - 111_195) < 500)
    }

    // MARK: - Import

    @Test("un fichier importé devient une activité complète")
    func importBuildsAnActivity() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let track = try GPXParser.parse(data: sampleGPX())
        let activity = try GPXImporter(context: context).import(track, fallbackName: "repli")

        #expect(activity.name == "Sortie du matin")
        #expect(activity.sportType == .run)
        // Not `.strava`: the sync must never claim, refresh or overwrite it.
        #expect(activity.source == .file)
        #expect(activity.stravaID == 0)
        #expect(activity.distance > 900 && activity.distance < 1_100)
        #expect(activity.totalElevationGain == 50)
        #expect(activity.hasTrack)
        #expect(activity.streams?.coordinates.count == 11)
        #expect(activity.boundingBox != nil)
    }

    @Test("un type inconnu ne bloque pas l'import")
    func unknownTypeLandsInOther() throws {
        #expect(GPXImporter.sport(for: "Trail Running") == .trailRun)
        #expect(GPXImporter.sport(for: "cycling - road") == .ride)
        #expect(GPXImporter.sport(for: "9") == .other)
        #expect(GPXImporter.sport(for: nil) == .other)
    }

    @Test("les séries incomplètes ne sont pas enregistrées de travers")
    func skipsMisalignedSeries() throws {
        // One point out of two carries an altitude. Storing the series anyway
        // would put every altitude against the wrong point in every chart.
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="45.10" lon="5.70"><ele>100</ele></trkpt>
            <trkpt lat="45.11" lon="5.71"/>
          </trkseg></trk>
        </gpx>
        """.data(using: .utf8)!
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try GPXImporter(context: context)
            .import(try GPXParser.parse(data: data), fallbackName: "repli")

        #expect(activity.streams?.altitude == nil)
        #expect(activity.streams?.coordinates.count == 2)
    }

    // MARK: - Export

    @Test("un aller-retour export puis import conserve le tracé")
    func roundTripsThroughAFile() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let original = try GPXImporter(context: context)
            .import(try GPXParser.parse(data: sampleGPX()), fallbackName: "repli")

        let reread = try GPXParser.parse(
            data: Data(GPXWriter.document(for: original).utf8)
        )

        // The whole promise of a local journal: what goes in comes back out.
        #expect(reread.name == original.name)
        #expect(reread.points.count == 11)
        #expect(abs(reread.coordinates[5].latitude - 43.2945) < 0.000_001)
        #expect(reread.elevations.count == 11)
        #expect(reread.times.count == 11)
        #expect(reread.times.first == original.startDate)
    }

    @Test("une activité sans streams exporte quand même son tracé simplifié")
    func exportsTheSimplifiedTrackAsAFallback() {
        // The common case for a library synced summaries-only: refusing to
        // export it would be refusing most of the journal.
        let activity = Activity(stravaID: 7, name: "Sans détail", sportType: .ride)
        let coordinates = [
            Coordinate(latitude: 45.10, longitude: 5.70),
            Coordinate(latitude: 45.11, longitude: 5.71),
        ]
        activity.apply(simplifiedCoordinates: coordinates)

        let points = GPXWriter.points(for: activity)
        #expect(points.count == 2)
        #expect(points[0].elevation == nil)
    }

    @Test("le nom de fichier survit aux caractères interdits")
    func buildsASafeFileName() {
        let activity = Activity(stravaID: 1, name: "12/07 : sortie", sportType: .run)
        activity.startLocalDate = Date(timeIntervalSince1970: 1_773_129_600)

        let name = GPXWriter.fileName(for: activity)
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(name.hasSuffix(".gpx"))
    }

    @Test("le XML échappe ce qui casserait le fichier")
    func escapesMarkup() {
        let activity = Activity(
            stravaID: 1, name: "Côte d'\"Azur\" & <trail>", sportType: .run
        )
        activity.apply(simplifiedCoordinates: [Coordinate(latitude: 43, longitude: 5)])

        let document = GPXWriter.document(for: activity)
        // Ampersands must not be double-escaped: `&amp;lt;` would read back as
        // the literal text "&lt;", not as "<".
        #expect(document.contains("&amp; &lt;trail&gt;"))
        #expect(!document.contains("&amp;lt;"))
        #expect(try! GPXParser.parse(data: Data(document.utf8)).name == activity.name)
    }

    // MARK: - Rapport d'import

    @Test("le rapport ne s'affiche que s'il y a quelque chose à signaler")
    func reportsOnlyFailures() {
        // Nothing to say when it all worked: the new rows on screen are the
        // confirmation, and an alert on every success is noise.
        #expect(RootView.importReport(imported: 3, failures: []) == nil)

        let partial = RootView.importReport(imported: 2, failures: ["a.gpx : cassé"])
        #expect(partial?.contains("2 activités importées") == true)
        #expect(partial?.contains("a.gpx") == true)

        #expect(
            RootView.importReport(imported: 0, failures: ["a.gpx : cassé"])?
                .contains("Aucun fichier") == true
        )
    }
}
