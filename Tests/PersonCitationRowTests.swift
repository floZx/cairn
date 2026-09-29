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
        #expect(surlignes("Vu @Céline puis @Christèle.", "Christèle") == ["@Christèle"])
    }

    /// Même clé, autre orthographe : c'est la même personne.
    @Test("sans accent, c'est encore elle")
    func sansAccent() {
        #expect(surlignes("@Christele m'a écrit", "Christèle") == ["@Christele"])
    }

    @Test("un préfixe n'est pas elle")
    func prefixe() {
        #expect(surlignes("@Christelle et @Chris", "Christèle").isEmpty)
    }
}
