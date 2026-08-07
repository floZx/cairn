import Testing
@testable import Cairn

@Suite("Retour visible après réintégration")
@MainActor
struct DiscardedRestoreFeedbackTests {
    @Test("le message dit ce qui ramène réellement l'activité")
    func saysWhatBringsItBack() {
        // Reinstating only lifts the tombstone and pulls the sync cursor back.
        // Until a sync runs, the journal is unchanged — and the row vanishing
        // from this list was the only feedback, which reads as "it is back".
        let started = DiscardedActivitiesSection.confirmation(
            name: "Lunch Walk", syncStarted: true
        )
        #expect(started.contains("Lunch Walk"))
        #expect(started.contains("synchronisation lancée"))

        // No Strava account, or a sync already in flight: promising one that was
        // never started would be the same lie in the other direction.
        let deferred = DiscardedActivitiesSection.confirmation(
            name: "Lunch Walk", syncStarted: false
        )
        #expect(deferred.contains("prochaine synchronisation"))
        #expect(deferred != started)
    }
}
