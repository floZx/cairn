import Testing
import Foundation
@testable import Cairn

@Suite("Ce qu'il reste à télécharger est visible")
@MainActor
struct PendingStreamsIndicatorTests {
    @Test("au repos, l'état dit s'il reste des courbes à récupérer")
    func idleSaysWhetherAnythingRemains() {
        // Nothing else could answer "is it finished?": the queue is persisted
        // and survives quitting, so an idle app with a backlog and an idle app
        // with nothing left to do read exactly the same.
        let progress = SyncProgress()
        progress.lastRunAt = Date(timeIntervalSince1970: 1_770_000_000)

        progress.pendingStreams = 0
        let done = progress.statusText
        #expect(done.contains("tout est à jour"))

        progress.pendingStreams = 102
        let pending = progress.statusText
        #expect(pending.contains("102"))
        #expect(!pending.contains("tout est à jour"))
        // The date stays in both: it is the other half of the answer.
        #expect(done.contains("Dernière synchro") && pending.contains("Dernière synchro"))
    }

    @Test("le pluriel suit le compte")
    func pluralFollowsTheCount() {
        let progress = SyncProgress()
        progress.pendingStreams = 1
        #expect(progress.statusText.contains("1 activité en attente"))
        progress.pendingStreams = 2
        #expect(progress.statusText.contains("2 activités en attente"))
    }
}
