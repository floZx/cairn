import Testing
@testable import Cairn

@MainActor
@Suite("Séparateur et tirets typographiques")
struct TiretsTypographiquesTests {
    @Test("« ---» passé par les tirets intelligents reste un trait", arguments: [
        "---", "—", "—-", "-—", "——", "– -", "———", "***", "_ _ _",
    ])
    func trait(_ ligne: String) {
        #expect(MarkdownParser.estUnTrait(ligne))
    }

    /// Un demi-cadratin seul, deux tirets simples : du texte, pas un trait.
    @Test("ce qui n'en est pas un", arguments: ["–", "--", "-", "— oui", "a—-"])
    func pasUnTrait(_ ligne: String) {
        #expect(!MarkdownParser.estUnTrait(ligne))
    }

    @Test("la note l'affiche en trait")
    func rendu() {
        let blocs = MarkdownParser.blocks(from: "Avant\n\n—-\n\nAprès")
        #expect(blocs.contains { if case .rule = $0 { true } else { false } })
    }
}
