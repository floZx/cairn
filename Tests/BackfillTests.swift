import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Rattrapage du détail et des photos")
@MainActor
struct BackfillTests {
    private func makeActivity(
        _ context: ModelContext, id: Int64, source: ActivitySource = .strava,
        detail: Date? = nil, photos: Date? = nil
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Sortie \(id)", sportType: .ride)
        activity.source = source
        activity.detailFetchedAt = detail
        activity.photosFetchedAt = photos
        activity.startDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(id))
        context.insert(activity)
        return activity
    }

    @Test("seules les activités Strava incomplètes sont candidates")
    func picksTheRightCandidates() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let now = Date()
        _ = makeActivity(context, id: 1)                                  // rien
        _ = makeActivity(context, id: 2, detail: now)                     // photos manquent
        _ = makeActivity(context, id: 3, photos: now)                     // détail manque
        _ = makeActivity(context, id: 4, detail: now, photos: now)        // complète
        // Nothing will ever arrive for a local activity: no Strava, no endpoint.
        _ = makeActivity(context, id: 5, source: .file)
        try context.save()

        let found = try context.fetch(SyncEngine.backfillDescriptor())
        #expect(Set(found.map(\.stravaID)) == [1, 2, 3])
    }

    @Test("les plus récentes d'abord, et la limite est respectée")
    func newestFirstAndBounded() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        for id in Int64(1)...5 { _ = makeActivity(context, id: id) }
        try context.save()

        // Newest first because those are the ones someone is about to open;
        // bounded so a launch stays a couple of dozen requests.
        let found = try context.fetch(SyncEngine.backfillDescriptor(limit: 2))
        #expect(found.map(\.stravaID) == [5, 4])
    }

    @Test("l'état dit ce qui reste, et se tait quand il ne reste rien")
    func remainingTextIsNeverAmbiguous() {
        #expect(SyncProgress.remainingText(streams: 0, backfill: 0) == "tout est à jour")
        #expect(SyncProgress.remainingText(streams: 3, backfill: 0).contains("courbes"))
        #expect(SyncProgress.remainingText(streams: 0, backfill: 7).contains("compléter"))

        // Both at once must not hide one behind the other.
        let both = SyncProgress.remainingText(streams: 3, backfill: 7)
        #expect(both.contains("3") && both.contains("7"))
    }
}
