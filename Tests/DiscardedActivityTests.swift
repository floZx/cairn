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
        let other = Activity(stravaID: 2, name: "Autre sortie", sportType: .run)
        context.insert(activity)
        context.insert(other)

        #expect(activity.uuid.isEmpty == false)
        // A shared default would defeat the whole point of a local identity —
        // exactly the failure mode a lightweight migration produced for real.
        #expect(activity.uuid != other.uuid)
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

    @Test("deux éditions successives de champs différents restent toutes deux protégées")
    func markEditedAccumulates() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 4, name: "Sortie", sportType: .run)
        context.insert(activity)
        activity.markEdited([.name])
        activity.markEdited([.distance])

        #expect(activity.editedFields == [.name, .distance])
    }

    @Test("une clé inconnue en base est ignorée, pas fatale")
    func toleratesUnknownKeys() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let activity = Activity(stravaID: 3, name: "Sortie", sportType: .run)
        context.insert(activity)
        // As a store written by a later version would contain.
        activity.editedFieldsRaw = ["name", "someFutureField"]
        try context.save()

        let reloaded = try ModelContext(container)
            .fetch(FetchDescriptor<Activity>()).first
        #expect(reloaded?.editedFields == [.name])
    }

    @Test("une pierre tombale retient l'identifiant, le nom et une date récente")
    func discardedRemembers() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let before = Date()
        let stone = DiscardedActivity(stravaID: 42, name: "Sortie du matin")
        context.insert(stone)
        try context.save()

        let found = try context.fetch(FetchDescriptor<DiscardedActivity>()).first
        #expect(found?.stravaID == 42)
        // The name is kept so the settings screen can say what was discarded:
        // a bare identifier would make the list impossible to review.
        #expect(found?.name == "Sortie du matin")
        // The list is sorted by this date; `Date.distantPast` would still pass a
        // bare non-nil check but would sort as if nothing had ever happened.
        let discardedAt = try #require(found?.discardedAt)
        #expect(discardedAt >= before)
        #expect(discardedAt <= Date())
    }
}
