import Testing
import Foundation
@testable import Cairn

/// L'adresse qu'une mention porte dans une note rendue.
///
/// C'est par elle que passe le clic : le texte est un seul `Text`, et un lien
/// est la seule chose qu'une plage puisse être. L'aller-retour doit donc tenir
/// pour tout ce qu'un pseudo peut contenir.
@Suite("Le lien d'une mention")
@MainActor
struct MentionLinkTests {
    private func handle(_ nom: String) -> PersonHandle { PersonHandle(name: nom)! }

    @Test("l'adresse se relit")
    func allerRetour() throws {
        for nom in ["sam", "Stéphanie", "Jean-Luc", "marie_c", "Hélène"] {
            let lien = try #require(MarkdownText.lien(pour: handle(nom)))
            #expect(MarkdownText.mention(dans: lien) == handle(nom))
        }
    }

    /// Le pseudo voyage tel qu'il est écrit : la fiche a besoin de la clé pour
    /// retrouver la personne, et de l'orthographe pour la nommer.
    @Test("l'orthographe survit au voyage")
    func lOrthographeSurvit() throws {
        let lien = try #require(MarkdownText.lien(pour: handle("Stéphanie")))
        #expect(MarkdownText.mention(dans: lien)?.name == "Stéphanie")
        #expect(MarkdownText.mention(dans: lien)?.key == "stephanie")
    }

    /// Les liens ordinaires d'une note doivent partir au navigateur, pas
    /// ouvrir une fiche.
    @Test("une adresse ordinaire n'est pas une mention")
    func uneAdresseOrdinaireNEstPasUneMention() throws {
        for adresse in ["https://exemple.fr", "mailto:f@exemple.fr", "cairn://autre"] {
            let url = try #require(URL(string: adresse))
            #expect(MarkdownText.mention(dans: url) == nil)
        }
    }

    /// Ce que le rendu pose vraiment sur le texte.
    @Test("une note citée porte le lien de la personne")
    func laNotePorteLeLien() throws {
        let rendu = MarkdownText.withHighlightedMentions(
            AttributedString("Sortie avec @Sam, puis dîner.")
        )
        let liens = rendu.runs.compactMap(\.link)
        #expect(liens.count == 1)
        #expect(MarkdownText.mention(dans: try #require(liens.first))?.key == "sam")
    }

    @Test("une adresse de courriel ne devient pas un lien de personne")
    func uneAdresseDeCourrielNEstPasCitee() {
        let rendu = MarkdownText.withHighlightedMentions(
            AttributedString("écrire à f.maisonnial@gmail.com")
        )
        #expect(rendu.runs.compactMap(\.link).isEmpty)
    }
}
