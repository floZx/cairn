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

@Suite("Déduire les types manquants sur tout le plan")
struct TrainingDeductionTests {
    private func magasin() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func jour(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    /// Les six types, comme dans les réglages.
    @discardableResult
    private func poserLesTypes(_ context: ModelContext) -> [String: DayType] {
        let noms = [
            ("Repos", 1750), ("Renfo/léger", 1950), ("Footing ou natation", 2200),
            ("Qualité", 2400), ("Footing + natation", 2750), ("Sortie longue", 2950),
        ]
        var table: [String: DayType] = [:]
        for (rang, (nom, kcal)) in noms.enumerated() {
            let type = DayType(name: nom, kcalTarget: kcal, sortOrder: rang)
            context.insert(type)
            table[nom] = type
        }
        return table
    }

    private func seance(
        _ raw: String, _ titre: String, sport: SportType = .run,
        duree: Double? = nil, dans context: ModelContext
    ) {
        context.insert(PlannedSession(
            dateKey: jour(raw), sportTypeRaw: sport.rawValue, title: titre,
            plannedDuration: duree
        ))
    }

    @Test func unPlanVideNeProposeRien() throws {
        let context = try magasin()
        poserLesTypes(context)
        #expect(try TrainingNutrition.propositions(dans: context).isEmpty)
    }

    /// Le point qui compte : hors du plan, « aucune séance » ne veut pas dire
    /// « repos », mais « on ne sait pas ».
    @Test func laDeductionSArreteAuxBornesDuPlan() throws {
        let context = try magasin()
        poserLesTypes(context)
        seance("2026-08-10", "Footing", dans: context)
        seance("2026-08-12", "SL 20 km", dans: context)

        let jours = try TrainingNutrition.propositions(dans: context).map(\.dateKey.raw)
        #expect(jours == ["2026-08-10", "2026-08-11", "2026-08-12"])
    }

    @Test func leJourCreuxDuPlanDevientDuRepos() throws {
        let context = try magasin()
        poserLesTypes(context)
        seance("2026-08-10", "Footing", dans: context)
        seance("2026-08-12", "Footing", dans: context)

        let propositions = try TrainingNutrition.propositions(dans: context)
        let creux = try #require(propositions.first { $0.dateKey.raw == "2026-08-11" })
        #expect(creux.type.name == "Repos")
        #expect(creux.resume == "Aucune séance")
    }

    @Test func uneJourneeDejaRegleeNApparaitPasDansLApercu() throws {
        let context = try magasin()
        let types = poserLesTypes(context)
        seance("2026-08-10", "Footing", dans: context)
        context.insert(NutritionDay(dateKey: jour("2026-08-10"), dayType: types["Qualité"]))

        #expect(try TrainingNutrition.propositions(dans: context).isEmpty)
    }

    /// Un vélo seul ne se déduit pas — la journée est simplement sautée, et
    /// celles qui l'entourent restent proposées.
    @Test func ceQuOnNeSaitPasDeduireEstSaute() throws {
        let context = try magasin()
        poserLesTypes(context)
        seance("2026-08-10", "Footing", dans: context)
        seance("2026-08-11", "Home-trainer", sport: .ride, dans: context)
        seance("2026-08-12", "Footing", dans: context)

        let jours = try TrainingNutrition.propositions(dans: context).map(\.dateKey.raw)
        #expect(jours == ["2026-08-10", "2026-08-12"])
    }

    @Test func lEcritureCreeEtCompleteSansEcraser() throws {
        let context = try magasin()
        let types = poserLesTypes(context)
        seance("2026-08-10", "Footing", dans: context)
        seance("2026-08-11", "SL 22 km", dans: context)
        // Une journée qui existe sans type : elle doit être complétée, pas
        // doublée.
        context.insert(NutritionDay(dateKey: jour("2026-08-11")))

        let propositions = try TrainingNutrition.propositions(dans: context)
        #expect(try TrainingNutrition.ecrire(propositions, dans: context) == 2)

        let journees = try context.fetch(
            FetchDescriptor<NutritionDay>(sortBy: [SortDescriptor(\.dateKeyRaw)])
        )
        #expect(journees.count == 2)
        #expect(journees.map(\.dayType?.name) == ["Footing ou natation", "Sortie longue"])
        #expect(types["Repos"] != nil)
    }
}
