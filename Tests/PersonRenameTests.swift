import Testing
import Foundation
import SwiftData
@testable import Cairn

@MainActor
@Suite("Renommer une personne")
struct PersonRenameTests {
    private let h = { (nom: String) in PersonHandle(name: nom)! }

    @Test("chaque mention, sous toutes ses orthographes, et rien d'autre")
    func remplacer() {
        let texte = "Avec @Stéphanie puis (@stephanie), écrit à s@stephanie.fr, et @Stéphane."
        #expect(
            PersonRename.remplacer(dans: texte, ancien: h("Stéphanie"), par: h("Stéphanie-M"))
                == "Avec @Stéphanie-M puis (@Stéphanie-M), écrit à s@stephanie.fr, et @Stéphane."
        )
        #expect(PersonRename.remplacer(dans: "Rien ici", ancien: h("Stéphanie"), par: h("Steph")) == nil)
    }

    @Test("les refus")
    func refus() {
        let connus = [h("Stéphanie"), h("Tom"), h("Chris")]
        #expect(PersonRename.refus("Tom", pour: h("Stéphanie"), connus: connus) == .dejaPris(h("Tom")))
        #expect(PersonRename.refus("Sté phanie", pour: h("Stéphanie"), connus: connus) == .nomInvalide)
        #expect(PersonRename.refus("Stéphanie", pour: h("Stéphanie"), connus: connus) == .inchange)
        #expect(PersonRename.refus("@Stéphanie-M", pour: h("Stéphanie"), connus: connus) == nil)
        // La même clé, une autre orthographe : une correction, permise.
        #expect(PersonRename.refus("stephanie", pour: h("Stéphanie"), connus: connus) == nil)
    }

    @Test("les sorties, les repas, les pesées et la fiche suivent")
    func renommer() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let sortie = Activity(stravaID: 1, name: "Rando", sportType: .hike)
        sortie.startDate = .now
        sortie.activityDescription = "Rando avec @Stéphanie."
        context.insert(sortie)
        context.insert(MealNote(dateKey: DateKey(raw: "2026-09-29")!, mealSlot: nil, note: "Dîner, @stephanie"))
        context.insert(WeightEntry(dateKey: DateKey(raw: "2026-09-29")!, weightKg: 70, note: "sans elle"))
        let fiche = Person(handle: h("Stéphanie"), note: "Collègue.")
        fiche.aliases = ["Steph"]
        context.insert(fiche)
        try context.save()

        let reecrits = PersonRename.renommer(h("Stéphanie"), en: h("Stéphanie-M"), context: context)
        try context.save()

        #expect(reecrits == 2)
        #expect(sortie.activityDescription == "Rando avec @Stéphanie-M.")
        // Par le brouillon : la note est protégée de la synchronisation Strava.
        #expect(sortie.editedFields.contains(.notes))
        let repas = try #require(try context.fetch(FetchDescriptor<MealNote>()).first)
        #expect(repas.note == "Dîner, @Stéphanie-M")
        #expect(fiche.name == "Stéphanie-M")
        #expect(fiche.key == "stephanie-m")
        #expect(fiche.aliases == ["Steph"])
    }
}
