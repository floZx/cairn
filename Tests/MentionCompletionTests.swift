import Testing
import Foundation
@testable import Cairn

@Suite("L'autocomplétion après @")
struct MentionCompletionTests {
    private func handles(_ noms: [String]) -> [PersonHandle] {
        noms.compactMap { PersonHandle(name: $0) }
    }

    private func enCours(_ texte: String) -> MentionCompletion.EnCours? {
        MentionCompletion.enCours(dans: texte, a: texte.endIndex)
    }

    @Test func unPseudoEnCoursDeFrappe() {
        #expect(enCours("sorti avec @sa")?.fragment == "sa")
    }

    /// Juste après l'arobase : la liste complète, sans rien avoir tapé.
    @Test func lArobaseSeuleOuvreLaListe() {
        #expect(enCours("sorti avec @")?.fragment == "")
    }

    @Test func riendEnDehorsDUneCitation() {
        #expect(enCours("sorti avec sam") == nil)
        #expect(enCours("") == nil)
    }

    /// La même règle que partout : une adresse de courriel n'ouvre rien.
    @Test func uneAdresseNOuvrePasLaListe() {
        #expect(enCours("écris à florian@gm") == nil)
    }

    @Test func uneEspaceReferme() {
        #expect(enCours("avec @sam et") == nil)
    }

    @Test func leCurseurSeDeduitDeLInsertion() {
        let index = MentionCompletion.pointDInsertion(de: "avec @sa", vers: "avec @sam")
        #expect(index == "avec @sam".endIndex)
    }

    /// Retoucher le milieu d'une phrase : l'insertion est bien repérée là où
    /// elle a eu lieu, pas à la fin.
    @Test func uneInsertionAuMilieuEstTrouvee() {
        let ancien = "avec @sa demain"
        let nouveau = "avec @sam demain"
        let index = try! #require(
            MentionCompletion.pointDInsertion(de: ancien, vers: nouveau)
        )
        #expect(MentionCompletion.enCours(dans: nouveau, a: index)?.fragment == "sam")
    }

    @Test func unEffacementNeProposeRien() {
        #expect(MentionCompletion.pointDInsertion(de: "avec @sam", vers: "avec @sa") == nil)
    }

    @Test func lesPropositionsSuiventLeDebut() {
        let connus = handles(["sam", "samuel", "landry", "sacha"])
        let trouves = MentionCompletion.propositions(pour: "sa", parmi: connus)
        #expect(trouves.map(\.name) == ["sam", "sacha", "samuel"])
    }

    @Test func lesAccentsNeGenentPas() {
        let connus = handles(["Hélène", "henri"])
        #expect(
            MentionCompletion.propositions(pour: "hel", parmi: connus).map(\.name)
                == ["Hélène"]
        )
    }

    @Test func unFragmentVideProposeTout() {
        let connus = handles(["sam", "landry"])
        #expect(MentionCompletion.propositions(pour: "", parmi: connus).count == 2)
    }

    @Test func leChoixRemplaceLeFragment() {
        let texte = "sorti avec @sa"
        let enCours = try! #require(
            MentionCompletion.enCours(dans: texte, a: texte.endIndex)
        )
        let complete = MentionCompletion.complete(
            texte, remplacant: enCours.plage, par: PersonHandle(name: "samuel")!
        )
        #expect(complete.texte == "sorti avec @samuel ")
        // Derrière l'espace : on vient de nommer quelqu'un, la phrase continue.
        #expect(complete.curseur == "sorti avec @samuel ".utf16.count)
    }

    /// Le curseur se compte en UTF-16, celles d'AppKit — un emoji y vaut deux
    /// unités là où Swift n'y voit qu'un caractère. Sans ça il retombait au
    /// milieu du nom qu'on venait de choisir.
    @Test func leCurseurSeCompteCommeAppKitCompte() {
        let texte = "hier 😀 avec @sa demain"
        let complete = MentionCompletion.complete(
            texte, remplacant: texte.range(of: "@sa")!, par: PersonHandle(name: "sam")!
        )
        #expect(complete.texte == "hier 😀 avec @sam demain")
        // Le « d » de « demain » : le curseur est passé l'espace.
        #expect(complete.curseur == (complete.texte as NSString).range(of: "demain").location)
    }

    /// Compléter au milieu d'une phrase ne double pas l'espace.
    @Test func lEspaceNEstPasDoublee() {
        let texte = "avec @sa demain"
        let complete = MentionCompletion.complete(
            texte, remplacant: texte.range(of: "@sa")!, par: PersonHandle(name: "sam")!
        )
        #expect(complete.texte == "avec @sam demain")
    }
}
