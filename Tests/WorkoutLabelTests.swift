import Testing
import Foundation
@testable import Cairn

@Suite("Type de séance modifiable")
struct WorkoutLabelTests {
    private func stravaActivity(workoutType: Int?) -> Activity {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        activity.source = .strava
        activity.workoutType = workoutType
        activity.movingTime = 3600
        return activity
    }

    @Test("sans choix local, c'est Strava qui décide")
    func fallsBackToStrava() {
        #expect(stravaActivity(workoutType: 1).workoutLabel == .race)
        #expect(stravaActivity(workoutType: nil).workoutLabel == nil)
    }

    @Test("le choix local prend le dessus sur Strava")
    func localChoiceWins() {
        let activity = stravaActivity(workoutType: 1)
        var draft = ActivityDraft(activity)
        draft.workoutLabel = .longRun
        draft.apply(to: activity)

        #expect(activity.workoutLabel == .longRun)
        #expect(activity.labels.contains(.longRun))
        #expect(!activity.labels.contains(.race))
    }

    @Test("« Aucun » est un choix, pas une absence de choix")
    func noneIsADeliberateChoice() {
        // The case the fallback would quietly undo: clearing the type has to
        // stick, or Strava's `workout_type` would put the label straight back.
        let activity = stravaActivity(workoutType: 1)
        var draft = ActivityDraft(activity)
        draft.workoutLabel = nil
        draft.apply(to: activity)

        #expect(activity.isEdited(.workoutLabel))
        #expect(activity.workoutLabel == nil)
        #expect(activity.labels.isEmpty)
    }

    @Test("une resynchro Strava ne défait pas le choix local")
    func resyncLeavesTheChoiceAlone() {
        let activity = stravaActivity(workoutType: 1)
        var draft = ActivityDraft(activity)
        draft.workoutLabel = .workout
        draft.apply(to: activity)

        // What the sync does on the next pass: Strava's code is refreshed and
        // kept, but it no longer decides.
        activity.workoutType = 2
        #expect(activity.workoutLabel == .workout)
    }

    @Test("une activité saisie à la main garde son type")
    func manualActivityKeepsItsLabel() {
        // `apply` only claims fields on synced activities, so a manual activity
        // never has `.workoutLabel` in `editedFields` — the local value has to
        // win anyway, or a hand-entered race could never be marked as one.
        var draft = ActivityDraft(startingOn: Date())
        draft.name = "Trail des Cimes"
        draft.movingMinutes = 90
        draft.workoutLabel = .race
        let activity = draft.makeActivity()

        #expect(!activity.isEdited(.workoutLabel))
        #expect(activity.workoutLabel == .race)
        #expect(activity.labels.contains(.race))
    }

    @Test("enregistrer sans toucher au type ne le revendique pas")
    func anUntouchedTypeIsNotClaimed() {
        let activity = stravaActivity(workoutType: 1)
        var draft = ActivityDraft(activity)
        draft.name = "Autre nom"
        draft.apply(to: activity)

        #expect(activity.editedFields == [.name])
        #expect(activity.workoutLabel == .race)
    }

    @Test("seuls les trois types de séance sont proposés au choix")
    func onlyWorkoutTypesAreOffered() {
        // `manual` says where an activity came from; letting the user claim it
        // by hand would make the badge a lie.
        #expect(ActivityLabel.workoutTypes == [.race, .longRun, .workout])
    }
}
