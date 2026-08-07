import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("Protection des champs édités")
@MainActor
struct EditProtectionTests {
    private func summary(id: Int64, name: String, distance: Double) throws -> SummaryActivityDTO {
        try Fixture.decode(
            SummaryActivityDTO.self, from: "summary_activity",
            patching: ["id": id, "name": name, "distance": distance]
        )
    }

    @Test("un champ édité survit à un réimport, un champ intact est mis à jour")
    func protectsOnlyWhatWasEdited() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let imported = try mapper.upsert(
            summary: summary(id: 7, name: "Nom de Strava", distance: 10_000)
        )
        imported.name = "Mon nom"
        imported.markEdited([.name])

        // Strava sends a new name AND a corrected distance.
        let again = try mapper.upsert(
            summary: summary(id: 7, name: "Nom de Strava v2", distance: 11_000)
        )

        // Both assertions matter. The first is the protection; the second is what
        // distinguishes field-by-field protection from freezing the activity —
        // without it, a rename would stop every future correction.
        #expect(again.name == "Mon nom")
        #expect(again.distance == 11_000)
    }

    @Test("une activité qui ne vient pas de Strava n'est jamais touchée")
    func leavesLocalActivitiesAlone() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let manual = Activity(stravaID: 0, name: "Séance salle", sportType: .workout)
        manual.source = .manual
        manual.distance = 0
        context.insert(manual)

        // A Strava activity that happens to carry id 0 must not capture it.
        _ = try mapper.upsert(summary: summary(id: 0, name: "Autre", distance: 5_000))

        #expect(manual.name == "Séance salle")
        #expect(manual.distance == 0)
        #expect(manual.source == .manual)
    }

    @Test("réimporter deux fois ne duplique pas, sans contrainte d'unicité")
    func reimportDoesNotDuplicate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        _ = try mapper.upsert(summary: summary(id: 9, name: "Sortie", distance: 8_000))
        _ = try mapper.upsert(summary: summary(id: 9, name: "Sortie", distance: 8_000))

        // This is the guarantee that replaces the dropped #Unique constraint.
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 1)
    }
}
