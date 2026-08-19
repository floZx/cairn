import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Reprise du plan depuis un agenda")
struct TrainingCalendarImportTests {
    private func jour(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func evenement(
        _ raw: String, _ titre: String, minute: Int = 0
    ) -> TrainingCalendarImport.Evenement {
        TrainingCalendarImport.Evenement(
            dateKey: jour(raw), titre: titre,
            debut: jour(raw).date().addingTimeInterval(Double(minute) * 60)
        )
    }

    @Test func unAgendaVierrgeNeDonneRien() {
        #expect(TrainingCalendarImport.aCreer([], deja: []).isEmpty)
    }

    /// Le deuxième import ne double pas le plan : c'est la seule chose qu'on
    /// risque vraiment de faire deux fois.
    @Test func ceQuiExisteDejaNEstPasRecree() {
        let retenus = TrainingCalendarImport.aCreer(
            [evenement("2026-08-19", "Footing 45'"), evenement("2026-08-20", "SL 18 km")],
            deja: [(jour: "2026-08-19", titre: "Footing 45'")]
        )
        #expect(retenus.map(\.titre) == ["SL 18 km"])
    }

    @Test func deuxSeancesDuMemeJourGardentLeurOrdre() {
        let retenus = TrainingCalendarImport.aCreer([
            evenement("2026-08-19", "Natation", minute: 12 * 60),
            evenement("2026-08-19", "Footing", minute: 7 * 60),
        ], deja: [])
        #expect(retenus.map(\.titre) == ["Footing", "Natation"])
    }

    @Test func unEvenementSansTitreEstIgnore() {
        #expect(TrainingCalendarImport.aCreer([evenement("2026-08-19", "  ")], deja: []).isEmpty)
    }

    /// Le même titre deux fois dans l'agenda lui-même — un événement récurrent
    /// mal dupliqué — ne fait qu'une séance.
    @Test func lesDoublonsDeLAgendaSeFondent() {
        let retenus = TrainingCalendarImport.aCreer([
            evenement("2026-08-19", "Footing"), evenement("2026-08-19", "Footing"),
        ], deja: [])
        #expect(retenus.count == 1)
    }

    @Test func lEcritureNumeroteLaJournee() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        try TrainingCalendarImport.ecrire([
            evenement("2026-08-19", "Footing 45'", minute: 7 * 60),
            evenement("2026-08-19", "Natation 2000 m", minute: 12 * 60),
            evenement("2026-08-20", "SL 18 km D+600"),
        ], dans: context)

        let seances = try context.fetch(
            FetchDescriptor<PlannedSession>(
                sortBy: [SortDescriptor(\.dateKeyRaw), SortDescriptor(\.sortOrder)]
            )
        )
        #expect(seances.map(\.title) == ["Footing 45'", "Natation 2000 m", "SL 18 km D+600"])
        #expect(seances.map(\.sortOrder) == [0, 1, 0])
        // Ce que la lecture du titre a su tirer arrive avec.
        #expect(seances[0].sport == .run)
        #expect(seances[0].plannedDuration == 2700)
        #expect(seances[1].sport == .swim)
        #expect(seances[2].plannedDistance == 18000)
        #expect(seances[2].plannedElevation == 600)
    }
}
