import Testing
import Foundation
@testable import Cairn

@Suite("JournalNote")
struct JournalNoteTests {
    private func note(_ raw: String, _ text: String) -> JournalNote {
        JournalNote(date: DateKey(raw: raw)!, text: text)
    }

    @Test("une note faite de blancs est vide")
    func whitespaceOnlyIsEmpty() {
        #expect(note("2026-08-11", "   \n\n\t ").isEmpty)
        #expect(!note("2026-08-11", "a").isEmpty)
    }

    @Test("le résumé saute le frontmatter et prend la première vraie ligne")
    func summarySkipsFrontmatter() {
        let text = """
            ---
            tags: [sam]
            ---

            Promenade avec #Sam.
            Puis rentré.
            """
        #expect(note("2026-08-11", text).summary == "Promenade avec #Sam.")
    }

    @Test("la recherche ignore la casse et les accents")
    func searchFoldsCaseAndDiacritics() {
        let subject = note("2026-08-11", "Journée à Sète, très chaude.")
        #expect(subject.matches(query: "SETE"))
        #expect(subject.matches(query: "journee"))
        #expect(!subject.matches(query: "Lyon"))
    }

    @Test("une recherche vide garde tout")
    func emptyQueryMatchesEverything() {
        #expect(note("2026-08-11", "").matches(query: "   "))
    }

    @Test("l'extrait est centré sur la correspondance")
    func excerptSurroundsTheMatch() {
        let filler = String(repeating: "a ", count: 60)
        let subject = note("2026-08-11", filler + "trouvé ici " + filler)
        let excerpt = subject.excerpt(matching: "trouvé")
        #expect(excerpt != nil)
        #expect(excerpt!.contains("trouvé"))
        #expect(excerpt!.hasPrefix("…"))
        #expect(excerpt!.hasSuffix("…"))
        #expect(excerpt!.count < 140)
    }

    @Test("un extrait en début de note ne porte pas d'ellipse devant")
    func excerptAtTheStart() {
        let subject = note("2026-08-11", "trouvé tout de suite")
        #expect(subject.excerpt(matching: "trouvé") == "trouvé tout de suite")
    }

    @Test("l'extrait met les retours à la ligne sur une seule ligne")
    func excerptIsOneLine() {
        let subject = note("2026-08-11", "avant\ntrouvé\naprès")
        #expect(subject.excerpt(matching: "trouvé") == "avant trouvé après")
    }

    @Test("sans correspondance, pas d'extrait")
    func noExcerptWithoutAMatch() {
        #expect(note("2026-08-11", "rien ici").excerpt(matching: "trouvé") == nil)
    }

    @Test("plusieurs tags cochés se combinent en ET")
    func tagsCombineWithAnd() {
        let subject = note("2026-08-11", "#sam #vélo")
        #expect(subject.has([JournalTag(name: "sam")!]))
        #expect(subject.has([JournalTag(name: "sam")!, JournalTag(name: "vélo")!]))
        #expect(!subject.has([JournalTag(name: "sam")!, JournalTag(name: "abri")!]))
    }

    @Test("aucun tag coché ne filtre rien")
    func noTagFiltersNothing() {
        #expect(note("2026-08-11", "").has([]))
    }

    @Test("le filtre cumule recherche et tags, la plus récente en tête")
    func filterCombinesAndSorts() {
        let notes = [
            note("2026-08-09", "promenade avec #sam"),
            note("2026-08-11", "promenade seul"),
            note("2026-08-10", "promenade avec #sam et #léa"),
        ]
        let all = JournalNote.filter(notes, query: "", tags: [])
        #expect(all.map(\.date.raw) == ["2026-08-11", "2026-08-10", "2026-08-09"])

        let narrowed = JournalNote.filter(
            notes, query: "promenade", tags: [JournalTag(name: "sam")!]
        )
        #expect(narrowed.map(\.date.raw) == ["2026-08-10", "2026-08-09"])

        let both = JournalNote.filter(
            notes, query: "léa", tags: [JournalTag(name: "sam")!]
        )
        #expect(both.map(\.date.raw) == ["2026-08-10"])
    }
}
