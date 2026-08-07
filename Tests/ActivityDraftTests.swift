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

    @Test("le texte de confirmation de suppression dit laquelle des deux suppressions elle est")
    func deleteConfirmationMessageMatchesTheConsequence() {
        // A Strava deletion leaves a tombstone a resync cannot cross; a local
        // one just loses the activity. Different consequences, so the two
        // messages must actually differ — a refactor collapsing them into one
        // text would be a half-truth, and this is what would catch it.
        #expect(ActivitySource.strava.deleteConfirmationMessage.contains("resynchronisation"))
        #expect(ActivitySource.manual.deleteConfirmationMessage.contains("perdue"))
        #expect(ActivitySource.file.deleteConfirmationMessage.contains("perdue"))
        #expect(
            ActivitySource.strava.deleteConfirmationMessage
                != ActivitySource.manual.deleteConfirmationMessage
        )
        // Manual and file share the same fate — nothing they wrote for a
        // sync-only guarantee applies to either — so they share the text too.
        #expect(
            ActivitySource.manual.deleteConfirmationMessage
                == ActivitySource.file.deleteConfirmationMessage
        )
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

    @Test("enregistrer sans rien changer ne fige aucun champ, ni ne modifie les valeurs")
    func changingNothingMarksNothing() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        // A duration that does not divide evenly by 60: it is the round trip
        // through minutes and back that a round number like 3600 would hide.
        activity.movingTime = 1_931
        let draft = ActivityDraft(activity)

        draft.apply(to: activity)

        #expect(activity.name == "Sortie")
        #expect(activity.distance == 10_000)
        #expect(activity.movingTime == 1_931)
        #expect(activity.totalElevationGain == 250)
        // Otherwise merely opening the sheet would stop the sync updating this
        // activity for ever, with nothing on screen to say so.
        #expect(activity.editedFields.isEmpty)
        #expect(activity.editedAt == nil)
    }

    @Test("un espace en fin de nom ne fige pas le champ")
    func trailingWhitespaceNameDoesNotMark() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        var draft = ActivityDraft(activity)
        draft.name = "Sortie "

        // The value written and the value compared must agree: `write(to:)`
        // trims before saving, so `changedFields` must trim the same way, or
        // a trailing space would freeze `.name` for ever with nothing on
        // screen to show for it.
        #expect(draft.changedFields(comparedTo: activity).isEmpty)
        draft.apply(to: activity)
        #expect(activity.editedFields.isEmpty)
        #expect(activity.name == "Sortie")
    }

    @Test("le nom importé d'une activité Strava, jamais rogné à la source, ne se marque pas non plus")
    func importedTrailingWhitespaceNameDoesNotMark() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // `ImportMapper` builds `Activity(stravaID:name:sportType:)` straight
        // from the Strava title, with no trimming — unlike `write(to:)`, which
        // always trims. A one-sided fix (comparison trimmed, `activity.name`
        // not) would just move the same defect to this exact activity: the
        // very case the sync writes every day.
        let activity = Activity(stravaID: 42, name: "Sortie du soir ", sportType: .run)
        activity.distance = 10_000
        activity.movingTime = 3_600
        context.insert(activity)
        var draft = ActivityDraft(activity)
        draft.distanceKm = 12

        #expect(draft.changedFields(comparedTo: activity) == [.distance])
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

    @Test("un brouillon invalide dit pourquoi, avec un message différent selon le motif")
    func explainsWhyItIsInvalid() {
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        let emptyNameMessage = draft.validationMessage
        #expect(emptyNameMessage != nil)   // no name yet

        // `movingMinutes` is already 0 from `init(startingOn:)`: no need to
        // assign it again to reach the "no duration" branch.
        draft.name = "Séance salle"
        let noDurationMessage = draft.validationMessage
        #expect(noDurationMessage != nil)   // duration still zero
        // A single constant would satisfy every `!= nil` check above; the
        // design is a message that says *what* is missing, so the reasons
        // must actually differ.
        #expect(noDurationMessage != emptyNameMessage)

        draft.movingMinutes = 45
        #expect(draft.validationMessage == nil)

        draft.distanceKm = -1
        let negativeDistanceMessage = draft.validationMessage
        #expect(negativeDistanceMessage != nil)   // negative distance
        #expect(negativeDistanceMessage != noDurationMessage)

        draft.distanceKm = 0
        draft.elevationGain = -1
        #expect(draft.validationMessage != nil)   // negative elevation gain, its own branch
    }

    @Test("une durée, une distance ou un dénivelé non finis sont invalides")
    func nonFiniteValuesAreInvalid() {
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        draft.name = "Séance salle"
        draft.movingMinutes = 45

        // Not caught by any `<= 0` or `< 0` comparison — NaN and infinity make
        // those false too — and would otherwise reach `Int(...)` in
        // `write(to:)`, which traps instead of throwing.
        draft.movingMinutes = .nan
        #expect(draft.validationMessage != nil)

        draft.movingMinutes = 45
        draft.distanceKm = .infinity
        #expect(draft.validationMessage != nil)

        draft.distanceKm = 0
        draft.elevationGain = -Double.infinity
        #expect(draft.validationMessage != nil)
    }

    @Test("changedFields détecte les neuf champs, pas seulement ceux exercés ailleurs")
    func changedFieldsCoversEveryField() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        var draft = ActivityDraft(activity)
        draft.name = "Autre nom"
        draft.sport = .swim
        draft.startLocalDate = activity.startLocalDate.addingTimeInterval(3_600)
        draft.distanceKm = activity.distance / 1_000 + 1
        draft.movingMinutes = Double(activity.movingTime) / 60 + 1
        draft.elevationGain = activity.totalElevationGain + 1
        draft.notes = "Une note"
        draft.isCommute = !activity.isCommute
        draft.isTrainer = !activity.isTrainer

        // Every other test in this file exercises a handful of fields.
        // Removing any one case from `changedFields` would leave those
        // green — the "mark too little" failure mode, an edit lost in
        // silence — which is exactly what this closes.
        #expect(draft.changedFields(comparedTo: activity) == Set(ActivityField.allCases))
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
        // `Activity.labels` reads `isManual`, not `source` — without this a
        // hand-entered session would carry no badge at all.
        #expect(created.isManual)
        #expect(created.labels.contains(.manual))
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

    @Test("éditer un champ sans rapport avec la date préserve le décalage horaire")
    func editingUnrelatedFieldPreservesTimezoneOffset() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        // UTC+2: the local wall time is two hours ahead of the UTC instant.
        activity.startDate = activity.startLocalDate.addingTimeInterval(-7_200)
        var draft = ActivityDraft(activity)
        draft.name = "Nom modifié"

        draft.apply(to: activity)

        // `startLocalDate` did not move, so `.startDate` is rightly unmarked —
        // but assigning the wall time straight into the UTC instant would
        // still have silently dropped the two-hour offset that `startDate`
        // carries for the list's sort, the period filter's bounds, and the
        // sync cursor's rewind.
        #expect(activity.startDate == activity.startLocalDate.addingTimeInterval(-7_200))
    }

    @Test("modifier la distance recalcule la vitesse moyenne")
    func recomputesAverageSpeedWhenDistanceChanges() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        var draft = ActivityDraft(activity)
        draft.distanceKm = 20

        draft.apply(to: activity)

        // A stored column, like `elapsedTime`: it goes stale the moment
        // distance or moving time change, and nothing else recomputes it.
        #expect(activity.averageSpeed == 20_000.0 / 3_600.0)
    }

    @Test("un brouillon neuf calcule sa propre vitesse moyenne")
    func createdActivityHasAverageSpeed() throws {
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        draft.name = "Course"
        draft.distanceKm = 5
        draft.movingMinutes = 30

        let created = draft.makeActivity()

        // Otherwise a manual entry would keep the zero it was never given a
        // chance to move away from, on a column the list can sort by.
        #expect(created.averageSpeed == 5_000.0 / 1_800.0)
    }
}
