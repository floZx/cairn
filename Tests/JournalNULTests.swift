import Testing
@testable import Cairn

@Suite("Échappement du NUL dans les notes")
struct JournalNULTests {
    /// Le couple doit rester son propre inverse. Les trois caractères que la
    /// paire distingue — le NUL, le marqueur U+E000 littéral et son
    /// désambiguïsateur U+E001 littéral — sont dans le même texte, côte à
    /// côte : aucun ne doit ressortir comme un autre.
    @Test func laSubstitutionDuNulEtSonInverseFontLAllerRetour() {
        let text = "avant\0apres\u{E000}\u{E001}encore, à bientôt — « citation »"
        #expect(JournalNUL.unescapingNUL(JournalNUL.escapingNUL(text)) == text)
    }

    /// Un NUL ne reste jamais tel quel en base : SwiftData tronquerait la
    /// note à cet endroit.
    @Test func aucunNulNeSurvitALEchappement() {
        #expect(!JournalNUL.escapingNUL("a\0b").unicodeScalars.contains("\0"))
    }
}
