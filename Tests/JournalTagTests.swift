import Testing
import Foundation
@testable import Cairn

@Suite("JournalTag")
struct JournalTagTests {
    @Test("un tag inline est reconnu")
    func inlineTag() {
        #expect(
            JournalTagScanner.tags(in: "Promenade avec #Sam pendant midi.")
                == Set([JournalTag(name: "Sam")!])
        )
    }

    @Test("la ponctuation termine le tag")
    func punctuationEndsTag() {
        #expect(
            JournalTagScanner.tags(in: "Vu #Sam, puis #Léa.")
                == Set([JournalTag(name: "Sam")!, JournalTag(name: "Léa")!])
        )
    }

    @Test("un titre Markdown n'est pas un tag")
    func headingIsNotATag() {
        #expect(JournalTagScanner.tags(in: "# Lundi\n\nRien.").isEmpty)
    }

    @Test("un tag entièrement numérique n'en est pas un")
    func numericIsNotATag() {
        #expect(JournalTagScanner.tags(in: "Objectif #2026 tenu.").isEmpty)
        #expect(
            JournalTagScanner.tags(in: "Objectif #2026-bilan tenu.")
                == Set([JournalTag(name: "2026-bilan")!])
        )
    }

    @Test("un # collé à un mot n'ouvre pas de tag")
    func hashInsideAWordIsNotATag() {
        #expect(JournalTagScanner.tags(in: "code#4 du portail").isEmpty)
    }

    @Test("un tag imbriqué compte aussi pour ses parents")
    func nestedTagCarriesItsAncestors() {
        #expect(
            JournalTagScanner.tags(in: "#projet/cairn/journal avance")
                == Set([
                    JournalTag(name: "projet")!,
                    JournalTag(name: "projet/cairn")!,
                    JournalTag(name: "projet/cairn/journal")!,
                ])
        )
    }

    @Test("le frontmatter en liste sur une ligne")
    func inlineFrontmatter() {
        let text = """
            ---
            tags: [sam, promenade]
            ---

            Rien de plus.
            """
        #expect(
            JournalTagScanner.tags(in: text)
                == Set([JournalTag(name: "sam")!, JournalTag(name: "promenade")!])
        )
    }

    @Test("le frontmatter en liste à puces")
    func bulletFrontmatter() {
        let text = """
            ---
            title: Lundi
            tags:
              - sam
              - projet/cairn
            ---

            Rien de plus.
            """
        #expect(
            JournalTagScanner.tags(in: text)
                == Set([
                    JournalTag(name: "sam")!,
                    JournalTag(name: "projet")!,
                    JournalTag(name: "projet/cairn")!,
                ])
        )
    }

    @Test("un tiret de séparation en milieu de note n'est pas du frontmatter")
    func frontmatterMustStartTheFile() {
        let text = """
            Une note.

            ---
            tags: [sam]
            ---
            """
        #expect(JournalTagScanner.tags(in: text).isEmpty)
    }

    @Test("le décompte va du plus utilisé au moins utilisé, puis par nom")
    func tallyOrdering() {
        let rows = JournalTagTally.rows(for: [
            Set([JournalTag(name: "sam")!, JournalTag(name: "vélo")!]),
            Set([JournalTag(name: "sam")!]),
            Set([JournalTag(name: "abri")!]),
        ])
        #expect(rows.map(\.tag.name) == ["sam", "abri", "vélo"])
        #expect(rows.map(\.count) == [2, 1, 1])
    }
}
