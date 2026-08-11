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

    @Test("le corps rendu ne montre pas le frontmatter")
    func bodyDropsFrontmatter() {
        // Rendered, a note carrying front matter would otherwise open on a
        // paragraph « --- tags: [sam] --- », which says nothing to anyone.
        let text = """
            ---
            tags: [sam]
            ---

            # Mardi
            Promenade.
            """
        #expect(
            MarkdownParser.blocks(from: JournalNote.body(of: text)) == [
                .heading(level: 1, text: "Mardi"),
                .paragraph("Promenade."),
            ]
        )
    }

    @Test("un tiret de séparation en milieu de note reste dans le corps")
    func bodyKeepsARuleInTheMiddle() {
        // The block only counts at the very top of the file, as it does for the
        // tags: below the first line it is something the author typed.
        let text = "Une note.\n\n---\ntags: [sam]\n---"
        #expect(JournalNote.body(of: text) == text)
    }

    @Test("un frontmatter jamais refermé ne perd que sa première ligne")
    func bodyOfAnUnterminatedFrontmatter() {
        // Whatever follows an unclosed `---` is almost certainly the note
        // itself; showing it is better than hiding it to the end of the file.
        #expect(JournalNote.body(of: "---\ntags: [sam]") == "tags: [sam]")
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

@Suite("Sélection à l'arrivée dans le journal")
@MainActor
struct JournalInitialSelectionTests {
    private func notes(_ raws: [String]) -> [JournalNote] {
        raws.map { JournalNote(date: DateKey(raw: $0)!, text: "x") }
    }

    @Test("la note la plus récente est retenue quand rien n'est sélectionné")
    func picksTheNewest() {
        // The list is already sorted newest first, so "the first row" and "the
        // most recent note" are the same thing — which is what makes `e` work
        // the moment one arrives.
        let rows = notes(["2026-08-11", "2026-08-10", "2026-08-09"])
        #expect(
            JournalListView.initialSelection(notes: rows, current: nil)
                == DateKey(raw: "2026-08-11")!
        )
    }

    @Test("une sélection existante n'est jamais écrasée")
    func leavesAnExistingSelectionAlone() {
        let rows = notes(["2026-08-11", "2026-08-10"])
        #expect(
            JournalListView.initialSelection(
                notes: rows, current: DateKey(raw: "2026-08-10")!
            ) == nil
        )
    }

    @Test("une liste vide ne sélectionne rien")
    func picksNothingFromAnEmptyList() {
        #expect(JournalListView.initialSelection(notes: [], current: nil) == nil)
    }

    @Test("la première note de la liste filtrée, pas du coffre entier")
    func picksTheFirstOfWhatIsShown() {
        // The view is handed `journalNotes`, already filtered by search and
        // ticked tags, so a filter that hides the newest note must not select
        // a row the user cannot see.
        let shown = notes(["2026-08-09"])
        #expect(
            JournalListView.initialSelection(notes: shown, current: nil)
                == DateKey(raw: "2026-08-09")!
        )
    }
}
