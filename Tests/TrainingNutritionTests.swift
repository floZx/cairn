import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Le plan pose le budget du jour")
struct TrainingNutritionTests {
    private func magasin() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func jour(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func seance(
        _ raw: String, type: DayType?, dans context: ModelContext
    ) -> PlannedSession {
        let seance = PlannedSession(
            dateKey: jour(raw), sportTypeRaw: SportType.run.rawValue,
            title: "Sortie longue", dayType: type
        )
        context.insert(seance)
        return seance
    }

    private func journees(_ context: ModelContext) throws -> [NutritionDay] {
        try context.fetch(FetchDescriptor<NutritionDay>())
    }

    @Test func laJourneeManquanteEstCreeeAvecSonType() throws {
        let context = try magasin()
        let sortieLongue = DayType(name: "Sortie longue", kcalTarget: 3200)
        context.insert(sortieLongue)

        #expect(try TrainingNutrition.appliquer(
            seance("2026-08-22", type: sortieLongue, dans: context), dans: context
        ))
        let posees = try journees(context)
        #expect(posees.count == 1)
        #expect(posees.first?.dateKeyRaw == "2026-08-22")
        #expect(posees.first?.dayType?.name == "Sortie longue")
    }

    @Test func uneJourneeSansTypeLeRecoit() throws {
        let context = try magasin()
        let repos = DayType(name: "Repos", kcalTarget: 2000)
        context.insert(repos)
        context.insert(NutritionDay(dateKey: jour("2026-08-22")))

        #expect(try TrainingNutrition.appliquer(
            seance("2026-08-22", type: repos, dans: context), dans: context
        ))
        #expect(try journees(context).first?.dayType?.name == "Repos")
    }

    /// Le point qui compte : une journée réglée à la main l'a été pour une
    /// raison que le plan ne connaît pas.
    @Test func unTypeDejaChoisiNEstJamaisEcrase() throws {
        let context = try magasin()
        let repos = DayType(name: "Repos", kcalTarget: 2000)
        let sortieLongue = DayType(name: "Sortie longue", kcalTarget: 3200)
        context.insert(repos)
        context.insert(sortieLongue)
        context.insert(NutritionDay(dateKey: jour("2026-08-22"), dayType: repos))

        #expect(try TrainingNutrition.appliquer(
            seance("2026-08-22", type: sortieLongue, dans: context), dans: context
        ) == false)
        #expect(try journees(context).first?.dayType?.name == "Repos")
    }

    @Test func uneSeanceSansTypeNeCreeRien() throws {
        let context = try magasin()
        #expect(try TrainingNutrition.appliquer(
            seance("2026-08-22", type: nil, dans: context), dans: context
        ) == false)
        #expect(try journees(context).isEmpty)
    }

    /// Deux séances le même jour — footing le matin, natation le midi — ne
    /// font qu'une journée nutrition : c'est la première qui la pose.
    @Test func deuxSeancesDuJourNeFontQuUneJournee() throws {
        let context = try magasin()
        let sortieLongue = DayType(name: "Sortie longue", kcalTarget: 3200)
        let repos = DayType(name: "Repos", kcalTarget: 2000)
        context.insert(sortieLongue)
        context.insert(repos)

        try TrainingNutrition.appliquer(
            seance("2026-08-22", type: sortieLongue, dans: context), dans: context
        )
        try TrainingNutrition.appliquer(
            seance("2026-08-22", type: repos, dans: context), dans: context
        )
        let posees = try journees(context)
        #expect(posees.count == 1)
        #expect(posees.first?.dayType?.name == "Sortie longue")
    }
}
