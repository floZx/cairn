import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("Édition locale et pierres tombales")
@MainActor
struct DiscardedActivityTests {
    @Test("une activité neuve a un uuid, vient de Strava et n'est pas éditée")
    func defaultsAreSane() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        context.insert(activity)

        #expect(activity.uuid.isEmpty == false)
        #expect(activity.source == .strava)
        #expect(activity.editedFields.isEmpty)
        #expect(activity.editedAt == nil)
    }

    @Test("les champs édités survivent à un aller-retour en base")
    func editedFieldsPersist() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let activity = Activity(stravaID: 2, name: "Sortie", sportType: .run)
        context.insert(activity)
        activity.markEdited([.name, .distance])
        try context.save()

        let reloaded = try ModelContext(container)
            .fetch(FetchDescriptor<Activity>()).first
        #expect(reloaded?.editedFields == [.name, .distance])
        #expect(reloaded?.isEdited(.name) == true)
        #expect(reloaded?.isEdited(.movingTime) == false)
        #expect(reloaded?.editedAt != nil)
    }

    @Test("une clé inconnue en base est ignorée, pas fatale")
    func toleratesUnknownKeys() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 3, name: "Sortie", sportType: .run)
        context.insert(activity)
        // As a store written by a later version would contain.
        activity.editedFieldsRaw = ["name", "someFutureField"]

        #expect(activity.editedFields == [.name])
    }

    @Test("une pierre tombale retient l'identifiant et le nom")
    func discardedRemembers() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let stone = DiscardedActivity(stravaID: 42, name: "Sortie du matin")
        context.insert(stone)
        try context.save()

        let found = try context.fetch(FetchDescriptor<DiscardedActivity>()).first
        #expect(found?.stravaID == 42)
        // The name is kept so the settings screen can say what was discarded:
        // a bare identifier would make the list impossible to review.
        #expect(found?.name == "Sortie du matin")
    }
}
