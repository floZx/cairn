import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Haut de la Z2 pour les titres")
@MainActor
struct ZoneTwoCeilingTests {
    private func sortie(
        _ id: Int64, joursAvant: Double, zones: [Double]?, in context: ModelContext
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Sortie \(id)", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: 1_790_000_000 - joursAvant * 86_400)
        activity.hrZoneFloors = zones
        context.insert(activity)
        return activity
    }

    @Test("les zones de la sortie, sinon celles de la plus proche, sinon rien")
    func ceiling() throws {
        guard #available(macOS 26.0, *) else { return }
        let context = ModelContext(try AppModelContainer.inMemory())
        let ancienne = sortie(1, joursAvant: 90, zones: [100, 120, 140, 160, 175], in: context)
        let recente = sortie(2, joursAvant: 5, zones: [100, 125, 150, 165, 180], in: context)
        let sansZones = sortie(3, joursAvant: 0, zones: nil, in: context)
        let avecZones = sortie(4, joursAvant: 1, zones: [100, 124, 147, 162, 178], in: context)
        let bibliotheque = [ancienne, recente, sansZones, avecZones]

        #expect(TitleIngredientsBuilder.zoneTwoCeiling(for: avecZones, in: bibliotheque) == 147)
        #expect(TitleIngredientsBuilder.zoneTwoCeiling(for: sansZones, in: [ancienne, recente, sansZones]) == 150)
        #expect(TitleIngredientsBuilder.zoneTwoCeiling(for: sansZones, in: [sansZones]) == nil)
    }
}
