import Foundation
import SwiftData
import Testing
@testable import Cairn

@Suite("Zones : ce que Garmin renvoie, et le tableau qu'on en tire")
struct ActivityZonesTests {
    /// La réponse de Garmin pour la course du 26 septembre, telle quelle.
    @Test func lesZonesDeGarminSeLisent() throws {
        let json = try JSONSerialization.jsonObject(with: Data("""
        [{"zoneNumber":2,"secsInZone":2106.69,"zoneLowBoundary":131},
         {"zoneNumber":1,"secsInZone":208.935,"zoneLowBoundary":103},
         {"zoneNumber":3,"secsInZone":497.933,"zoneLowBoundary":144},
         {"zoneNumber":4,"secsInZone":0.0,"zoneLowBoundary":153},
         {"zoneNumber":5,"secsInZone":0.0,"zoneLowBoundary":167}]
        """.utf8))
        let zones = try #require(GarminZones.parse(json))
        #expect(zones.floors == [103, 131, 144, 153, 167])
        #expect(zones.seconds.map { $0.rounded() } == [209, 2107, 498, 0, 0])
    }

    @Test func sansCapteurIlNYAPasDeZones() {
        #expect(GarminZones.parse([] as [Any]) == nil)
        #expect(GarminZones.parse(nil) == nil)
    }

    /// Le tableau de sa capture Garmin, ligne pour ligne.
    @Test func leTableauReprendCeluiDeGarmin() {
        let rows = ZoneTable.rows(
            floors: [103, 131, 144, 153, 167],
            seconds: [208.935, 2106.69, 497.933, 0, 0],
            kind: .heartRate
        )
        #expect(rows.map(\.zone) == [5, 4, 3, 2, 1])
        #expect(rows.map(\.range) == ["> 166 bpm", "153 - 166 bpm", "144 - 152 bpm", "131 - 143 bpm", "103 - 130 bpm"])
        #expect(rows.map(\.name) == ["Maximum", "Seuil", "Aérobie", "Facile", "Échauffement"])
        #expect(rows.map(\.percent) == [0, 0, 17, 74, 7])
        #expect(ZoneTable.duration(2106.69) == "35:07")
        #expect(ZoneTable.duration(3760) == "1:02:40")
    }
}

@Suite("Zones : rien d'avant la montre")
@MainActor
struct ZonesAvantLaMontreTests {
    @Test func uneSortieDAvantNEstPasDemandee() {
        let avant = Activity(stravaID: 1, name: "Avant", sportType: .run)
        avant.startDate = GarminZonesFetcher.firstWatchDay.addingTimeInterval(-3600)
        avant.averageHeartrate = 140
        let apres = Activity(stravaID: 2, name: "Après", sportType: .run)
        apres.startDate = GarminZonesFetcher.firstWatchDay.addingTimeInterval(3600)
        apres.averageHeartrate = 140
        #expect(!GarminZonesFetcher.needsZones(avant))
        #expect(GarminZonesFetcher.needsZones(apres))
    }

    @Test func lesZonesDeLImportSontEffacees() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let avant = Activity(stravaID: 1, name: "Avant", sportType: .run)
        avant.startDate = GarminZonesFetcher.firstWatchDay.addingTimeInterval(-86400)
        avant.hrZoneFloors = [106, 133, 149, 156, 168]
        avant.hrZoneSeconds = [1, 2, 3, 4, 5]
        avant.zonesCheckedAt = Date()
        let apres = Activity(stravaID: 2, name: "Après", sportType: .run)
        apres.startDate = GarminZonesFetcher.firstWatchDay.addingTimeInterval(86400)
        apres.hrZoneFloors = [103, 131, 144, 153, 167]
        apres.hrZoneSeconds = [1, 2, 3, 4, 5]
        context.insert(avant)
        context.insert(apres)
        try context.save()

        GarminZonesFetcher.clearImportedZones(in: context)

        #expect(avant.hrZoneFloors == nil)
        #expect(avant.hrZoneSeconds == nil)
        #expect(avant.zonesCheckedAt != nil)
        #expect(apres.hrZoneFloors == [103, 131, 144, 153, 167])
    }
}
