import Testing
import SwiftData
@testable import StravaLocal

@Suite("ActivityLabel")
struct ActivityLabelTests {
    @Test("les codes de type de séance diffèrent entre course et vélo")
    func mapsWorkoutTypesPerSport() {
        // Course : 1 compétition, 2 sortie longue, 3 entraînement.
        #expect(ActivityLabel.fromWorkoutType(1) == .race)
        #expect(ActivityLabel.fromWorkoutType(2) == .longRun)
        #expect(ActivityLabel.fromWorkoutType(3) == .workout)
        // Vélo : 11 compétition, 12 entraînement, et pas de sortie longue.
        #expect(ActivityLabel.fromWorkoutType(11) == .race)
        #expect(ActivityLabel.fromWorkoutType(12) == .workout)
    }

    @Test("l'absence de type ne produit pas d'étiquette")
    func noLabelWithoutType() {
        #expect(ActivityLabel.fromWorkoutType(nil) == nil)
        // 0 et 10 signifient « aucun type particulier », pas un type de plus.
        #expect(ActivityLabel.fromWorkoutType(0) == nil)
        #expect(ActivityLabel.fromWorkoutType(10) == nil)
        #expect(ActivityLabel.fromWorkoutType(99) == nil)
    }

    @Test("les drapeaux et le type se cumulent sur une activité")
    func combinesFlagsAndType() throws {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .ride)
        #expect(activity.labels.isEmpty)

        activity.workoutType = 11
        activity.isCommute = true
        activity.isTrainer = true

        #expect(activity.labels == [.race, .commute, .trainer])
    }

    @Test("le filtre exige toutes les étiquettes cochées")
    func filterRequiresEveryLabel() throws {
        let context = ModelContext(try AppModelContainer.inMemory())

        let raceCommute = Activity(stravaID: 1, name: "A", sportType: .ride)
        raceCommute.workoutType = 11
        raceCommute.isCommute = true
        let raceOnly = Activity(stravaID: 2, name: "B", sportType: .ride)
        raceOnly.workoutType = 11
        context.insert(raceCommute)
        context.insert(raceOnly)
        try context.save()

        var filter = ActivityFilter.none
        filter.labels = [.race]
        #expect([raceCommute, raceOnly].filter(filter.matchesPrecisely).count == 2)

        filter.labels = [.race, .commute]
        let both = [raceCommute, raceOnly].filter(filter.matchesPrecisely)
        #expect(both.map(\.stravaID) == [1])
    }

    @Test("aucune étiquette cochée ne filtre rien")
    func emptySelectionMatchesEverything() throws {
        let plain = Activity(stravaID: 1, name: "A", sportType: .run)
        #expect(ActivityFilter.none.matchesPrecisely(plain))
    }
}
