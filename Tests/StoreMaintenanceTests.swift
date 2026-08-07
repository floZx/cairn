import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Maintenance du store")
@MainActor
struct StoreMaintenanceTests {
    @Test("les uuid vides sont complétés, les autres laissés intacts")
    func fillsEmptyUUIDs() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let untouched = Activity(stravaID: 1, name: "Déjà en ordre", sportType: .run)
        let kept = untouched.uuid
        let empty = Activity(stravaID: 2, name: "Sans identité", sportType: .run)
        empty.uuid = ""
        context.insert(untouched)
        context.insert(empty)
        try context.save()

        let changed = try StoreMaintenance.run(context)

        #expect(changed == 1)
        #expect(untouched.uuid == kept)
        #expect(empty.uuid.isEmpty == false)
    }

    @Test("trois lignes partageant un uuid ressortent avec trois uuid distincts")
    func splitsDuplicatedUUIDs() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        // The shape actually measured in the user's store: a lightweight
        // migration applying one default to every existing row.
        let shared = "64D8A062-4BAC-4EAF-BB62-5803626D04E5"
        let one = Activity(stravaID: 1, name: "Une", sportType: .run)
        let two = Activity(stravaID: 2, name: "Deux", sportType: .run)
        let three = Activity(stravaID: 3, name: "Trois", sportType: .run)
        one.uuid = shared
        two.uuid = shared
        three.uuid = shared
        context.insert(one)
        context.insert(two)
        context.insert(three)
        try context.save()

        let changed = try StoreMaintenance.run(context)

        #expect(changed == 2)
        let uuids = Set([one.uuid, two.uuid, three.uuid])
        #expect(uuids.count == 3)
    }

    @Test("relancer sur un store déjà réparé ne change plus rien")
    func isIdempotent() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let shared = "64D8A062-4BAC-4EAF-BB62-5803626D04E5"
        let one = Activity(stravaID: 1, name: "Une", sportType: .run)
        let two = Activity(stravaID: 2, name: "Deux", sportType: .run)
        one.uuid = shared
        two.uuid = shared
        context.insert(one)
        context.insert(two)
        try context.save()
        try StoreMaintenance.run(context)

        let changed = try StoreMaintenance.run(context)

        #expect(changed == 0)
    }
}
