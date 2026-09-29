import Testing
import SwiftUI
@testable import Cairn

@MainActor
@Suite("Extrait d'une citation")
struct PersonCitationRowTests {
    private func surlignes(_ texte: String, _ nom: String) -> [String] {
        let extrait = PersonCitationRow.extrait(texte, soulignant: PersonHandle(name: nom)!)
        return extrait.runs
            .filter { $0.foregroundColor != nil }
            .map { String(extrait[$0.range].characters) }
    }

    @Test("son nom ressort, pas celui des autres")
    func seulementElle() {
        #expect(surlignes("Vu @Céline puis @Christèle.", "Christèle") == ["Christèle"])
    }

    /// Même clé, autre orthographe : c'est la même personne.
    @Test("sans accent, c'est encore elle")
    func sansAccent() {
        #expect(surlignes("@Christele m'a écrit", "Christèle") == ["Christele"])
    }

    @Test("l'arobase part de toutes les mentions, une adresse garde la sienne")
    func sansArobase() {
        let extrait = PersonCitationRow.extrait(
            "Vu @Céline, écrit à f@exemple.fr", soulignant: PersonHandle(name: "Christèle")!
        )
        #expect(String(extrait.characters) == "Vu Céline, écrit à f@exemple.fr")
    }

    @Test("un préfixe n'est pas elle")
    func prefixe() {
        #expect(surlignes("@Christelle et @Chris", "Christèle").isEmpty)
    }
}

@Suite("Aperçu sans arobases")
struct SansArobasesTests {
    @Test func mentions() {
        #expect(PersonHandle.sansArobases("Balade avec @Sam et @Antoine") == "Balade avec Sam et Antoine")
    }

    @Test func adresseEtAnneeRestent() {
        #expect(PersonHandle.sansArobases("écrit à f@exemple.fr en @2026") == "écrit à f@exemple.fr en @2026")
    }
}
