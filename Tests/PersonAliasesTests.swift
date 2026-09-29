import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Alias des personnes")
struct PersonAliasesTests {
    private let h = { (nom: String) in PersonHandle(name: nom)! }

    private func texte(_ jour: String, _ contenu: String) -> PeopleIndex.Texte {
        .init(dateKey: DateKey(raw: jour)!, source: .journal, contenu: contenu)
    }

    private var annuaire: PeopleIndex.Annuaire {
        PeopleIndex.Annuaire(fiches: [(name: "Christèle", aliases: ["Chris", "Chérie"])])
    }

    @Test("un alias mène à la personne, sous son nom à elle")
    func resolution() {
        #expect(annuaire.resoudre(h("Chris")).name == "Christèle")
        #expect(annuaire.resoudre(h("cherie")).name == "Christèle")
        #expect(annuaire.resoudre(h("christele")).name == "Christèle")
        #expect(annuaire.resoudre(h("Tom")).name == "Tom")
        #expect(annuaire.alias(de: h("Christèle")).map(\.name) == ["Chris", "Chérie"])
    }

    @Test("les notes d'un alias comptent pour elle, une fois par note")
    func citations() {
        let index = PeopleIndex.citations(dans: [
            texte("2026-09-01", "Vu @Chris puis @Christèle."),
            texte("2026-09-02", "Café avec @Chérie."),
            texte("2026-09-03", "Rien à voir avec @Tom."),
        ], annuaire: annuaire)
        #expect(index[h("Christèle")]?.count == 2)
        // Chris n'a pas d'entrée à lui : la clé « chris » n'existe pas.
        #expect(!index.keys.contains { $0.key == "chris" })
        #expect(Set(index.keys.map(\.name)) == ["Christèle", "Tom"])
    }

    /// Un seul sens : le nom d'une autre fiche n'est l'alias de personne.
    @Test("un alias qui est le nom d'une autre fiche est ignoré")
    func conflit() {
        let annuaire = PeopleIndex.Annuaire(fiches: [
            (name: "Christèle", aliases: ["Tom"]),
            (name: "Tom", aliases: []),
        ])
        #expect(annuaire.resoudre(h("Tom")).name == "Tom")
        #expect(annuaire.alias(de: h("Christèle")).isEmpty)
    }

    @MainActor
    @Test("fusionner : la note et les alias suivent, la fiche part")
    func fusion() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let chris = Person(handle: h("Chris"), note: "Rencontré au club.")
        chris.aliases = ["Chrichri"]
        context.insert(chris)
        context.insert(Person(handle: h("Christèle"), note: "Aime le café."))
        try context.save()

        #expect(PersonAliases.fusionner(h("Chris"), dans: h("Christèle"), context: context))
        try context.save()

        let fiches = try context.fetch(FetchDescriptor<Person>())
        #expect(fiches.count == 1)
        let christele = try #require(fiches.first)
        #expect(christele.aliases == ["Chris", "Chrichri"])
        #expect(christele.note == "Aime le café.\n\nRencontré au club.")
    }

    @MainActor
    @Test("un nom quitte la personne qui le portait")
    func unSeulPorteur() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let tom = Person(handle: h("Tom"))
        tom.aliases = ["Chris"]
        context.insert(tom)
        try context.save()

        PersonAliases.fusionner(h("Chris"), dans: h("Christèle"), context: context)
        try context.save()

        let fiches = try context.fetch(FetchDescriptor<Person>())
        // Tom n'avait que cet alias et pas de note : sa fiche part.
        #expect(fiches.map(\.name) == ["Christèle"])
        #expect(fiches.first?.aliases == ["Chris"])
    }

    @MainActor
    @Test("retirer le dernier alias d'une fiche sans note la supprime")
    func retrait() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        PersonAliases.fusionner(h("Chris"), dans: h("Christèle"), context: context)
        try context.save()
        let fiche = try #require(try context.fetch(FetchDescriptor<Person>()).first)

        PersonAliases.retirer(h("Chris"), de: fiche, context: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
    }

    @MainActor
    @Test("l'extrait de la carte fait ressortir ses alias aussi")
    func surlignage() {
        let extrait = PersonCitationRow.extrait(
            "Vu @Chris et @Tom", soulignant: h("Christèle"), alias: [h("Chris")]
        )
        let colores = extrait.runs.filter { $0.foregroundColor != nil }
            .map { String(extrait[$0.range].characters) }
        #expect(colores == ["Chris"])
    }
}

@Suite("Tri des personnes")
struct PeopleSortTests {
    private func ligne(_ nom: String, _ compte: Int, _ jour: String?) -> PeopleIndex.Ligne {
        .init(
            handle: PersonHandle(name: nom)!, compte: compte,
            derniere: jour.flatMap { DateKey(raw: $0) }, aUneNote: false
        )
    }

    private var lignes: [PeopleIndex.Ligne] {
        [ligne("Tom", 20, "2026-09-01"), ligne("Céline", 5, "2026-09-29"), ligne("Béa", 5, "2026-08-01")]
    }

    @Test func alphabetique() {
        #expect(PeopleIndex.trier(lignes, par: .alphabetique).map(\.handle.name) == ["Béa", "Céline", "Tom"])
    }

    /// À égalité, l'ordre alphabétique départage.
    @Test func nombre() {
        #expect(PeopleIndex.trier(lignes, par: .nombre).map(\.handle.name) == ["Tom", "Béa", "Céline"])
    }

    @Test func recentesNeTouchePas() {
        #expect(PeopleIndex.trier(lignes, par: .recentes).map(\.handle.name) == ["Tom", "Céline", "Béa"])
    }
}
