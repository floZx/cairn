import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionSeed")
@MainActor
struct NutritionSeedTests {
    @Test("le semis crée les repas et jours-types de suivinut")
    func seedsDefaults() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        try NutritionSeed.runIfEmpty(in: context)

        let slots = try context.fetch(FetchDescriptor<MealSlot>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(slots.map(\.name) == ["Petit-déj", "Déjeuner", "Collation", "Dîner"])
        #expect(slots.map(\.targetPct) == [28, 33, 0, 39])
        let dayTypes = try context.fetch(FetchDescriptor<DayType>())
        #expect(dayTypes.count == 4)
        #expect(dayTypes.contains { $0.name == "repos" && $0.kcalTarget == 1800 })
    }

    @Test("le semis ne double pas des repas existants")
    func doesNotDuplicate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        context.insert(MealSlot(name: "Unique", sortOrder: 0, targetPct: 100))
        try context.save()

        try NutritionSeed.runIfEmpty(in: context)
        #expect(try context.fetch(FetchDescriptor<MealSlot>()).count == 1)
    }
}
