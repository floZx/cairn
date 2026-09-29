import Foundation
import SwiftData
import Testing
@testable import Cairn

@MainActor @Suite("Zones : l'écart entre Strava et la dernière sortie Garmin")
struct ZoneDriftTests {
    private let jour = GarminZonesFetcher.firstWatchDay.addingTimeInterval(200 * 86400)

    /// Le cas mesuré le 29 septembre 2026 : Garmin a remonté la zone 2 d'un
    /// battement, Strava est resté à 130.
    @Test func laZone2DuVingtNeufSeptembre() throws {
        let drift = try #require(HeartRateZoneDrift.compare(
            garminFloors: [103, 131, 144, 153, 167],
            stravaFloors: [0, 130, 144, 153, 167],
            activityDate: jour
        ))
        #expect(drift.rows.map(\.zone) == [2, 3, 4, 5])
        #expect(drift.rows.filter(\.differs) == [.init(zone: 2, garmin: 131, strava: 130)])
        #expect(drift.message.contains("Z2 : 131 bpm (Strava : 130)"))
        #expect(drift.message.contains("Z3 : 144 bpm\n"))
    }

    /// La zone 1 ne compte pas : 0 chez Strava, la moitié de la FC max chez Garmin.
    @Test func desZonesQuiConcordentNeDonnentRien() {
        #expect(HeartRateZoneDrift.compare(
            garminFloors: [103, 130, 144, 153, 167],
            stravaFloors: [0, 130, 144, 153, 167],
            activityDate: jour
        ) == nil)
    }

    @Test func uneListeIncompleteNeSeComparePas() {
        #expect(HeartRateZoneDrift.compare(
            garminFloors: [103, 131, 144, 153, 167],
            stravaFloors: [0, 130, 150],
            activityDate: jour
        ) == nil)
    }

    @Test func lesZonesDeStravaSeLisent() throws {
        let dto = try JSONDecoder().decode(AthleteZonesDTO.self, from: Data("""
        {"heart_rate":{"custom_zones":true,"zones":[{"min":0,"max":129},
         {"min":130,"max":143},{"min":144,"max":152},{"min":153,"max":166},
         {"min":167,"max":-1}]},
         "power":{"zones":[{"min":0,"max":85}]}}
        """.utf8))
        #expect(dto.heart_rate?.zones.map(\.min) == [0, 130, 144, 153, 167])
    }

    /// La réponse brute de Strava après la mise à jour du 29 septembre : les
    /// `min` reprennent les `max` d'avant, et les zones sont pourtant celles de
    /// Garmin — pas d'alerte.
    @Test func lesPlanchersDeStravaSontLesMaxDAvantPlusUn() throws {
        let dto = try JSONDecoder().decode(AthleteZonesDTO.self, from: Data("""
        {"heart_rate":{"custom_zones":true,"zones":[{"min":0,"max":130},
         {"min":130,"max":143},{"min":143,"max":152},{"min":152,"max":166},
         {"min":166,"max":-1}]}}
        """.utf8))
        let floors = HeartRateZoneDrift.stravaFloors(try #require(dto.heart_rate).zones)
        #expect(floors == [0, 131, 144, 153, 167])
        #expect(HeartRateZoneDrift.compare(
            garminFloors: [103, 131, 144, 153, 167], stravaFloors: floors, activityDate: jour
        ) == nil)
    }

    /// La plus récente qui a des zones de FC, pas la plus récente tout court :
    /// une sortie sans ceinture n'en a pas.
    @Test func laReferenceEstLaDerniereSortieAvecDesZones() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let ancienne = Activity(stravaID: 1, name: "Ancienne", sportType: .run)
        ancienne.startDate = jour
        ancienne.hrZoneFloors = [106, 133, 149, 156, 168]
        ancienne.zonesCheckedAt = Date()
        let recente = Activity(stravaID: 2, name: "Récente", sportType: .run)
        recente.startDate = jour.addingTimeInterval(86400)
        recente.hrZoneFloors = [103, 131, 144, 153, 167]
        recente.zonesCheckedAt = Date()
        let sansCeinture = Activity(stravaID: 3, name: "Sans ceinture", sportType: .ride)
        sansCeinture.startDate = jour.addingTimeInterval(2 * 86400)
        sansCeinture.zonesCheckedAt = Date()
        let pasEncoreVue = Activity(stravaID: 4, name: "Pas encore vue", sportType: .run)
        pasEncoreVue.startDate = jour.addingTimeInterval(3 * 86400)
        for activity in [ancienne, recente, sansCeinture, pasEncoreVue] { context.insert(activity) }
        try context.save()

        let latest = try #require(HeartRateZoneDrift.latestGarminZones(in: context))
        #expect(latest.date == recente.startDate)
        #expect(latest.floors == [103, 131, 144, 153, 167])
    }
}
