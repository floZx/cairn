import Testing
@testable import Cairn

@Suite("Absence de courbes expliquée")
@MainActor
struct MissingChartsTests {
    @Test("des courbes en attente ne se lisent pas comme des courbes inexistantes")
    func distinguishesPendingFromAbsent() {
        // The whole point. Omitting the charts silently made an activity queued
        // behind a thousand others look exactly like a ride that recorded
        // neither altitude nor heart rate.
        let pending = ActivityDetailView.missingChartsMessage(
            hasStreams: false, isSynced: true
        )
        let absent = ActivityDetailView.missingChartsMessage(
            hasStreams: true, isSynced: true
        )

        #expect(pending != nil)
        #expect(absent != nil)
        #expect(pending != absent)
        #expect(pending?.contains("pas encore") == true)
    }

    @Test("une activité locale ne promet pas un téléchargement qui n'aura pas lieu")
    func aLocalActivityPromisesNothing() {
        // Nothing will ever arrive for it: no Strava, no streams endpoint. Saying
        // "they are coming" would be waiting for something that never comes.
        let message = ActivityDetailView.missingChartsMessage(
            hasStreams: false, isSynced: false
        )
        #expect(message?.contains("pas encore") == false)
        #expect(message?.contains("Strava") == true)
    }
}
