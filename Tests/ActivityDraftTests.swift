import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("ActivityField et ActivitySource")
struct ActivityFieldTests {
    @Test("chaque champ a une clé stable et un libellé")
    func fieldsAreStable() {
        // The raw values are persisted in `Activity.editedFields`. Renaming one
        // would silently unprotect every activity already edited, and the only
        // symptom would be an overwritten edit at the next sync.
        #expect(ActivityField.name.rawValue == "name")
        #expect(ActivityField.startDate.rawValue == "startDate")
        #expect(ActivityField.totalElevationGain.rawValue == "totalElevationGain")
        #expect(ActivityField.allCases.count == 9)
        #expect(ActivityField.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("seule la source Strava est concernée par la synchro")
    func onlyStravaIsSynced() {
        #expect(ActivitySource.strava.isSynced)
        #expect(ActivitySource.manual.isSynced == false)
        #expect(ActivitySource.file.isSynced == false)
        #expect(ActivitySource(rawValue: "strava") == .strava)
        // An unknown raw value must not crash a store written by a later version.
        #expect(ActivitySource(rawValue: "healthkit") == nil)
    }
}

@Suite("ActivityDraft")
@MainActor
struct ActivityDraftTests {
    private func makeActivity(in context: ModelContext) -> Activity {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        activity.distance = 10_000
        activity.movingTime = 3_600
        activity.totalElevationGain = 250
        activity.startLocalDate = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(activity)
        return activity
    }

    @Test("les unités du formulaire sont celles de l'utilisateur")
    func convertsUnitsAtTheBoundary() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let draft = ActivityDraft(makeActivity(in: context))

        // Kilometres and minutes in the form, metres and seconds in the model:
        // the conversion lives here so no view has to know about it.
        #expect(draft.distanceKm == 10)
        #expect(draft.movingMinutes == 60)
        #expect(draft.elevationGain == 250)
    }

    @Test("enregistrer sans rien changer ne fige aucun champ")
    func changingNothingMarksNothing() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        let draft = ActivityDraft(activity)

        draft.apply(to: activity)

        // Otherwise merely opening the sheet would stop the sync updating this
        // activity for ever, with nothing on screen to say so.
        #expect(activity.editedFields.isEmpty)
        #expect(activity.editedAt == nil)
    }

    @Test("seuls les champs réellement modifiés sont marqués")
    func marksOnlyWhatChanged() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        var draft = ActivityDraft(activity)
        draft.name = "Mon nom"
        draft.distanceKm = 12

        #expect(draft.changedFields(comparedTo: activity) == [.name, .distance])
        draft.apply(to: activity)

        #expect(activity.name == "Mon nom")
        #expect(activity.distance == 12_000)
        #expect(activity.editedFields == [.name, .distance])
        #expect(activity.editedAt != nil)
    }

    @Test("deux éditions successives s'accumulent")
    func editsAccumulate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        var first = ActivityDraft(activity)
        first.name = "Mon nom"
        first.apply(to: activity)

        var second = ActivityDraft(activity)
        second.elevationGain = 400
        second.apply(to: activity)

        // The second edit must not release the first.
        #expect(activity.editedFields == [.name, .totalElevationGain])
    }

    @Test("un brouillon invalide dit pourquoi")
    func explainsWhyItIsInvalid() {
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(draft.validationMessage != nil)   // no name yet

        draft.name = "Séance salle"
        draft.movingMinutes = 0
        #expect(draft.validationMessage != nil)   // no duration

        draft.movingMinutes = 45
        #expect(draft.validationMessage == nil)

        draft.distanceKm = -1
        #expect(draft.validationMessage != nil)   // negative distance
    }

    @Test("un brouillon neuf produit une activité locale sans identifiant Strava")
    func createsALocalActivity() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        draft.name = "Renforcement"
        draft.sport = .workout
        draft.movingMinutes = 45

        let created = draft.makeActivity()
        context.insert(created)

        #expect(created.stravaID == 0)
        #expect(created.source == .manual)
        #expect(created.movingTime == 2_700)
        // Nothing to protect: the sync ignores this activity outright, so a set of
        // "edited" fields would be noise.
        #expect(created.editedFields.isEmpty)
    }

    @Test("éditer une activité locale ne marque aucun champ")
    func editingALocalActivityMarksNothing() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        activity.source = .manual
        var draft = ActivityDraft(activity)
        draft.name = "Nom modifié"
        draft.distanceKm = 12

        draft.apply(to: activity)

        // The sync never looks at a local activity, so a set of claimed fields
        // on it would be noise nobody reads — and, worse, dead weight that a
        // later change of source could misread as protection.
        #expect(activity.name == "Nom modifié")
        #expect(activity.editedFields.isEmpty)
        #expect(activity.editedAt == nil)
    }
}
