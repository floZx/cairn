import Testing
@testable import Cairn

@Suite("L'index des personnes citées")
struct PeopleIndexTests {
    private func jour(_ raw: String) -> DateKey { DateKey(raw: raw)! }
    private func handle(_ nom: String) -> PersonHandle { PersonHandle(name: nom)! }

    private func texte(
        _ raw: String, _ source: PeopleIndex.Source, _ contenu: String
    ) -> PeopleIndex.Texte {
        PeopleIndex.Texte(dateKey: jour(raw), source: source, contenu: contenu)
    }

    @Test func chaqueTexteCitantCompte() {
        let index = PeopleIndex.citations(dans: [
            texte("2026-08-10", .journal, "journée avec @sam"),
            texte("2026-08-11", .sortie("Footing"), "sorti avec @sam et @landry"),
        ])
        #expect(index[handle("sam")]?.count == 2)
        #expect(index[handle("landry")]?.count == 1)
    }

    /// La liste des notes qui parlent d'elle, pas celle des occurrences.
    @Test func deuxCitationsDansUnTexteNEnFontQuUne() {
        let index = PeopleIndex.citations(dans: [
            texte("2026-08-10", .journal, "@sam le matin, puis @sam le soir")
        ])
        #expect(index[handle("sam")]?.count == 1)
    }

    /// L'extrait est ce qui parle d'elle, pas la journée entière.
    @Test func seulLeParagrapheCitantEstRetenu() {
        let index = PeopleIndex.citations(dans: [
            texte(
                "2026-08-10", .journal,
                """
                Réveil tard, courbatures de la veille.

                Café avec @sam en fin de matinée.

                Le soir, rien.
                """
            )
        ])
        #expect(index[handle("sam")]?.first?.texte == "Café avec @sam en fin de matinée.")
    }

    /// Une note faite d'items : sans découper la liste, « le paragraphe »
    /// serait la note entière.
    @Test func unItemDeListeCompteSeul() {
        let index = PeopleIndex.citations(dans: [
            texte(
                "2026-08-10", .journal,
                """
                - footing de 10 km
                - déjeuner avec @sam
                - lessive
                """
            )
        ])
        #expect(index[handle("sam")]?.first?.texte == "- déjeuner avec @sam")
    }

    /// Un paragraphe replié sur plusieurs lignes reste entier : l'extrait ne
    /// s'arrête pas au milieu d'une phrase.
    @Test func unParagrapheReplieResteEntier() {
        let plié = """
        On a marché jusqu'au col avec @sam,
        puis on est redescendus par l'autre versant.
        """
        let index = PeopleIndex.citations(dans: [
            texte("2026-08-10", .journal, "Grand beau.\n\n" + plié)
        ])
        #expect(index[handle("sam")]?.first?.texte == plié)
    }

    /// Deux passages citants sont recollés : la citation reste une note, elle
    /// est seulement réduite à ce qui la concerne.
    @Test func lesPassagesCitantsSontRecolles() {
        let index = PeopleIndex.citations(dans: [
            texte(
                "2026-08-10", .journal,
                """
                Café avec @sam.

                Trajet seul.

                Dîner chez @sam.
                """
            )
        ])
        #expect(index[handle("sam")]?.first?.texte == "Café avec @sam.\n\nDîner chez @sam.")
    }

    /// Un trait de séparation n'est pas une puce, et une phrase qui commence
    /// par un tiret cadratin non plus.
    @Test func unTraitDeSeparationNOuvrePasDUnite() {
        #expect(PeopleIndex.unites(de: "une phrase\n---\n— et sa suite").count == 1)
    }

    @Test func lesPlusRecentesDAbord() {
        let index = PeopleIndex.citations(dans: [
            texte("2026-08-10", .journal, "@sam"),
            texte("2026-08-14", .journal, "@sam"),
            texte("2026-08-12", .journal, "@sam"),
        ])
        #expect(index[handle("sam")]?.map(\.dateKey.raw) == [
            "2026-08-14", "2026-08-12", "2026-08-10",
        ])
    }

    @Test func unTexteVideNeCiteRien() {
        #expect(PeopleIndex.citations(dans: [texte("2026-08-10", .journal, "   ")]).isEmpty)
    }

    @Test func laListeSuitLaDerniereCitation() {
        let index = PeopleIndex.citations(dans: [
            texte("2026-08-10", .journal, "@landry"),
            texte("2026-08-14", .journal, "@sam"),
        ])
        let lignes = PeopleIndex.lignes(citations: index, fiches: [])
        #expect(lignes.map(\.handle.name) == ["sam", "landry"])
        #expect(lignes.allSatisfy { !$0.aUneNote })
    }

    /// Une fiche écrite puis la citation effacée : la personne reste, en bas.
    /// Perdre ce qu'on a écrit sur quelqu'un parce qu'une note a été retouchée
    /// serait une trappe.
    @Test func uneFicheSansCitationResteEnBas() {
        let index = PeopleIndex.citations(dans: [texte("2026-08-14", .journal, "@sam")])
        let lignes = PeopleIndex.lignes(
            citations: index, fiches: [(key: "helene", name: "Hélène")]
        )
        #expect(lignes.map(\.handle.name) == ["sam", "Hélène"])
        #expect(lignes.last?.compte == 0)
        #expect(lignes.last?.aUneNote == true)
    }

    @Test func uneFicheCiteeEstMarquee() {
        let index = PeopleIndex.citations(dans: [texte("2026-08-14", .journal, "@sam")])
        let lignes = PeopleIndex.lignes(
            citations: index, fiches: [(key: "sam", name: "sam")]
        )
        #expect(lignes.count == 1)
        #expect(lignes.first?.aUneNote == true)
    }
}
