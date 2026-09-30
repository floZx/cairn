import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Pesées Garmin")
@MainActor
struct GarminWeightsTests {
    @Test("la réponse par jour donne la dernière pesée, en kilos")
    func parsesDailySummaries() {
        let json: [String: Any] = [
            "dailyWeightSummaries": [
                [
                    "summaryDate": "2026-09-28",
                    "latestWeight": ["calendarDate": "2026-09-28", "weight": 71399.99],
                ],
                ["summaryDate": "2026-09-29", "latestWeight": NSNull()],
            ],
        ]
        #expect(GarminWeighIn.parse(json) == [
            GarminWeighIn(dateKey: DateKey(raw: "2026-09-28")!, weightKg: 71.4),
        ])
    }

    @Test("l'ancienne forme garde une pesée par jour")
    func parsesDateWeightList() {
        let json: [String: Any] = [
            "dateWeightList": [
                ["calendarDate": "2026-09-28", "weight": 71000],
                ["calendarDate": "2026-09-28", "weight": 71200],
            ],
        ]
        #expect(GarminWeighIn.parse(json).map(\.weightKg) == [71.2])
    }

    @Test("Garmin remplace le poids d'un jour, garde la note, et ne réécrit pas l'identique")
    func mergesByDay() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let day = DateKey(raw: "2026-09-28")!
        context.insert(WeightEntry(dateKey: day, weightKg: 72, note: "matin"))
        try context.save()

        let changed = try GarminWeightImporter.merge([
            GarminWeighIn(dateKey: day, weightKg: 71.4),
            GarminWeighIn(dateKey: day.advanced(by: 1), weightKg: 71.2),
        ], in: context)
        #expect(changed == 2)
        let entries = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.dateKeyRaw)]))
        #expect(entries.map(\.weightKg) == [71.4, 71.2])
        #expect(entries.first?.note == "matin")

        let again = try GarminWeightImporter.merge([
            GarminWeighIn(dateKey: day, weightKg: 71.4),
        ], in: context)
        #expect(again == 0)
    }
}
