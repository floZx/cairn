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

        // `source` is deliberately not asserted here: the mapper never writes
        // it in any branch, so that assertion could not fail and would just be
        // noise. `sportType` can: it comes from a stored raw value the guard
        // must also leave untouched.
        #expect(manual.name == "Séance salle")
        #expect(manual.distance == 0)
        #expect(manual.sportType == .workout)
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

    @Test("markEdited(.startDate) protège les deux propriétés de date ensemble")
    func protectsBothDateProperties() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let activity = try mapper.upsert(
            summary: summary(id: 40, name: "Sortie", distance: 5_000)
        )
        let originalStart = activity.startDate
        let originalLocal = activity.startLocalDate
        activity.markEdited([.startDate])

        let corrected = try Fixture.decode(
            SummaryActivityDTO.self, from: "summary_activity",
            patching: [
                "id": 40, "start_date": "2025-07-01T10:00:00Z",
                "start_date_local": "2025-07-01T12:00:00Z",
            ]
        )
        let again = try mapper.upsert(summary: corrected)

        // A single "Date" field protects two stored properties: missing either
        // one would leave sorting or filtering reading a value the sync just
        // put back behind the user's edit.
        #expect(again.startDate == originalStart)
        #expect(again.startLocalDate == originalLocal)
    }

    @Test("des notes éditées survivent à apply(detail:)")
    func protectsEditedNotes() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let activity = try mapper.upsert(
            summary: summary(id: 50, name: "Sortie", distance: 5_000)
        )
        activity.activityDescription = "Ma note perso"
        activity.markEdited([.notes])

        try mapper.apply(
            detail: DetailActivityDTO(
                id: 50, description: "Description Strava", calories: 812,
                device_name: "Garmin Edge 840", laps: nil
            ),
            to: activity
        )

        // The description is protected; calories is not editable and must
        // still land, or this would just be re-testing the source guard below.
        #expect(activity.activityDescription == "Ma note perso")
        #expect(activity.calories == 812)
    }

    /// One arm per `ActivityField`, on purpose written by hand rather than by
    /// reflection: an exhaustive `switch` fails to *compile* the moment a
    /// tenth case joins the enum without a matching arm here, which is a much
    /// harder guarantee to lose than a test someone forgot to write.
    ///
    /// Each arm marks the field as edited with a value distinct from both the
    /// original fixture and the reimported one, reimports through the same
    /// path production code uses (`upsert(summary:)` for every field but
    /// `.notes`, which only ever arrives through `apply(detail:)`), and reads
    /// back the one property that field guards.
    @Test("chaque ActivityField protège sa valeur face à un réimport", arguments: ActivityField.allCases)
    func everyFieldSurvivesReimport(_ field: ActivityField) throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(summary: summary(id: 60, name: "Sortie", distance: 5_000))

        switch field {
        case .name:
            activity.name = "Nom édité"
            activity.markEdited([.name])
            let again = try mapper.upsert(
                summary: summary(id: 60, name: "Nom Strava v2", distance: 5_000)
            )
            #expect(again.name == "Nom édité")

        case .sportType:
            activity.sportType = .swim
            activity.markEdited([.sportType])
            let dto = try Fixture.decode(
                SummaryActivityDTO.self, from: "summary_activity",
                patching: ["id": 60, "sport_type": "Run"]
            )
            let again = try mapper.upsert(summary: dto)
            #expect(again.sportType == .swim)

        case .startDate:
            let edited = Date(timeIntervalSince1970: 1_600_000_000)
            activity.startDate = edited
            activity.startLocalDate = edited
            activity.markEdited([.startDate])
            let dto = try Fixture.decode(
                SummaryActivityDTO.self, from: "summary_activity",
                patching: [
                    "id": 60, "start_date": "2025-07-01T10:00:00Z",
                    "start_date_local": "2025-07-01T12:00:00Z",
                ]
            )
            let again = try mapper.upsert(summary: dto)
            #expect(again.startDate == edited)
            #expect(again.startLocalDate == edited)

        case .distance:
            activity.distance = 12_000
            activity.markEdited([.distance])
            let dto = try Fixture.decode(
                SummaryActivityDTO.self, from: "summary_activity",
                patching: ["id": 60, "distance": 20_000.0]
            )
            let again = try mapper.upsert(summary: dto)
            #expect(again.distance == 12_000)

        case .movingTime:
            activity.movingTime = 1_800
            activity.markEdited([.movingTime])
            let dto = try Fixture.decode(
                SummaryActivityDTO.self, from: "summary_activity",
                patching: ["id": 60, "moving_time": 4_000]
            )
            let again = try mapper.upsert(summary: dto)
            #expect(again.movingTime == 1_800)

        case .totalElevationGain:
            activity.totalElevationGain = 250
            activity.markEdited([.totalElevationGain])
            let dto = try Fixture.decode(
                SummaryActivityDTO.self, from: "summary_activity",
                patching: ["id": 60, "total_elevation_gain": 900.0]
            )
            let again = try mapper.upsert(summary: dto)
            #expect(again.totalElevationGain == 250)

        case .notes:
            activity.activityDescription = "Note perso"
            activity.markEdited([.notes])
            try mapper.apply(
                detail: DetailActivityDTO(
                    id: 60, description: "Description Strava", calories: nil,
                    device_name: nil, laps: nil
                ),
                to: activity
            )
            #expect(activity.activityDescription == "Note perso")

        case .isCommute:
            activity.isCommute = true
            activity.markEdited([.isCommute])
            let dto = try Fixture.decode(
                SummaryActivityDTO.self, from: "summary_activity",
                patching: ["id": 60, "commute": false]
            )
            let again = try mapper.upsert(summary: dto)
            #expect(again.isCommute == true)

        case .isTrainer:
            activity.isTrainer = true
            activity.markEdited([.isTrainer])
            let dto = try Fixture.decode(
                SummaryActivityDTO.self, from: "summary_activity",
                patching: ["id": 60, "trainer": false]
            )
            let again = try mapper.upsert(summary: dto)
            #expect(again.isTrainer == true)
        }
    }

    @Test("une activité locale n'est pas touchée par apply(detail:)")
    func detailLeavesLocalActivitiesAlone() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let manual = Activity(stravaID: 51, name: "Séance salle", sportType: .workout)
        manual.source = .manual
        manual.activityDescription = "Note locale"
        context.insert(manual)

        // A Strava detail that happens to carry the same identifier must not
        // capture it, same as the summary guard above.
        try mapper.apply(
            detail: DetailActivityDTO(
                id: 51, description: "Description Strava", calories: 812,
                device_name: "Garmin Edge 840", laps: nil
            ),
            to: manual
        )

        #expect(manual.activityDescription == "Note locale")
        #expect(manual.calories == nil)
    }
}
