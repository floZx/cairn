import Testing
@testable import Cairn

@Suite("Reconnaître une personne citée")
struct PersonScannerTests {
    private func noms(_ texte: String) -> [String] {
        PersonScanner.mentions(in: texte).map(\.name).sorted()
    }

    @Test func uneCitationSimple() {
        #expect(noms("Sortie avec @sam") == ["sam"])
    }

    @Test func plusieursDansUnePhrase() {
        #expect(noms("@landry et @sam au départ") == ["landry", "sam"])
    }

    /// Le cas qui justifie toute la règle du mot ouvrant.
    @Test func uneAdresseDeCourrielNeCitePersonne() {
        #expect(noms("écris à f.maisonnial@gmail.com").isEmpty)
    }

    @Test("le @ peut suivre une ouvrante", arguments: [
        "(@sam et moi)", "« @sam »", "- @sam", "*@sam*", "> @sam a dit",
    ])
    func apresUneOuvrante(_ texte: String) {
        #expect(noms(texte) == ["sam"])
    }

    /// Le point clôt la phrase, il n'entre pas dans le pseudo.
    @Test func laPonctuationFinaleResteDehors() {
        #expect(noms("j'ai couru avec @sam.") == ["sam"])
        #expect(noms("avec @sam, puis seul") == ["sam"])
    }

    @Test func lesTiretsEtSoulignesSontPermis() {
        #expect(noms("@jean-marc et @marie_claire") == ["jean-marc", "marie_claire"])
    }

    /// La casse et les accents ne font pas deux personnes.
    @Test func laCasseEtLesAccentsSeRejoignent() {
        let handles = PersonScanner.mentions(in: "@Hélène le matin, @helene le soir")
        #expect(handles.count == 1)
        // La première orthographe rencontrée n'est pas garantie par un `Set`,
        // mais les deux se replient sur la même clé — c'est ce qui compte.
        #expect(handles.first?.key == "helene")
    }

    @Test func unNombreNEstPasUnePersonne() {
        #expect(noms("rendez-vous @2026").isEmpty)
    }

    @Test func unArobaseSeulNeCiteRien() {
        #expect(noms("le tarif @ 3 euros").isEmpty)
    }

    /// Un tag n'est pas une personne, et réciproquement.
    @Test func lesTagsNeSontPasConcernes() {
        #expect(noms("#trail avec @sam") == ["sam"])
        #expect(JournalTagScanner.tags(in: "#trail avec @sam").map(\.name) == ["trail"])
    }

    @Test func plusieursTextesDUnCoup() {
        let trouves = PersonScanner.mentions(inAny: [
            "footing avec @sam", nil, "déjeuner chez @landry", "rien ici",
        ])
        #expect(trouves.map(\.name).sorted() == ["landry", "sam"])
    }
}
