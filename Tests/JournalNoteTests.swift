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

    @Test("les images d'une note sortent dans l'ordre où elles sont écrites")
    func imagePathsComeOutInOrder() {
        let text = """
            Belle sortie.

            ![](pieces-jointes/2026-08-13-1.jpg)
            ![Le sommet](pieces-jointes/2026-08-13-2.jpg)
            """
        #expect(
            note("2026-08-13", text).imagePaths == [
                "pieces-jointes/2026-08-13-1.jpg",
                "pieces-jointes/2026-08-13-2.jpg",
            ]
        )
    }

    @Test("une note sans image n'en annonce aucune")
    func anoteWithoutPicturesHasNone() {
        #expect(note("2026-08-13", "Rien à signaler.").imagePaths.isEmpty)
        // Un lien au milieu d'une phrase n'est pas une image : c'est la règle
        // du parseur, pas une seconde lecture du texte.
        #expect(note("2026-08-13", "voir ![](x.jpg) ici").imagePaths.isEmpty)
    }

    @Test("le frontmatter ne cache pas les images")
    func frontmatterDoesNotHidePictures() {
        let text = """
            ---
            tags: [sam]
            ---

            ![](pieces-jointes/2026-08-13-1.jpg)
            """
        #expect(note("2026-08-13", text).imagePaths.count == 1)
    }

    @Test("le résumé dit ce que la ligne dit, sans la marque qui l'a formée")
    func summaryDropsBlockMarkers() {
        // Une ligne de liste ou un titre : le marqueur raconte comment la note
        // a été tapée, pas ce que la journée a été.
        #expect(note("2026-08-11", "# Mardi de repos").summary == "Mardi de repos")
        #expect(note("2026-08-11", "- Footing tranquille").summary == "Footing tranquille")
        #expect(note("2026-08-11", "> Jambes lourdes").summary == "Jambes lourdes")
        // Le balisage en ligne reste dans le texte : c'est le rendu de la
        // rangée qui l'interprète, et le couper ici casserait le gras.
        #expect(
            note("2026-08-11", "Sortie __« Entre Pôtes »__").summary
                == "Sortie __« Entre Pôtes »__"
        )
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
    private func days(_ raws: [String]) -> [JournalDay] {
        raws.map { JournalDay(date: DateKey(raw: $0)!, note: JournalNote(date: DateKey(raw: $0)!, text: "x")) }
    }

    @Test("la note la plus récente est retenue quand rien n'est sélectionné")
    func picksTheNewest() {
        // The list is already sorted newest first, so "the first row" and "the
        // most recent note" are the same thing — which is what makes `e` work
        // the moment one arrives.
        let rows = days(["2026-08-11", "2026-08-10", "2026-08-09"])
        #expect(
            JournalListView.initialSelection(days: rows, current: nil)
                == DateKey(raw: "2026-08-11")!
        )
    }

    @Test("une sélection existante n'est jamais écrasée")
    func leavesAnExistingSelectionAlone() {
        let rows = days(["2026-08-11", "2026-08-10"])
        #expect(
            JournalListView.initialSelection(
                days: rows, current: DateKey(raw: "2026-08-10")!
            ) == nil
        )
    }

    @Test("une liste vide ne sélectionne rien")
    func picksNothingFromAnEmptyList() {
        #expect(JournalListView.initialSelection(days: [], current: nil) == nil)
    }

    @Test("seule la ligne dont le texte a changé est à remesurer")
    func namesOnlyTheChangedRow() {
        let before = days(["2026-08-12", "2026-08-11", "2026-08-10"])
        var after = before
        after[1] = JournalDay(
            date: DateKey(raw: "2026-08-11")!,
            note: JournalNote(date: DateKey(raw: "2026-08-11")!, text: "x et y")
        )

        #expect(JournalListView.changedRows(from: before, to: after) == IndexSet([1]))
        #expect(JournalListView.changedRows(from: before, to: before).isEmpty)
    }

    @Test("une note qui apparaît décale les suivantes, toutes à remesurer")
    func namesEverythingBelowAnInsertion() {
        let before = days(["2026-08-11", "2026-08-10"])
        let after = days(["2026-08-12", "2026-08-11", "2026-08-10"])

        // La nouvelle note prend la place 0 : à partir de là, chaque ligne
        // affiche autre chose que ce qui y était mesuré.
        #expect(
            JournalListView.changedRows(from: before, to: after) == IndexSet(0..<3)
        )
        // Et dans l'autre sens, il ne reste rien à remesurer au-delà de la fin.
        #expect(
            JournalListView.changedRows(from: after, to: before) == IndexSet(0..<2)
        )
    }

    @Test("la première note de la liste filtrée, pas du coffre entier")
    func picksTheFirstOfWhatIsShown() {
        // The view is handed `journalNotes`, already filtered by search and
        // ticked tags, so a filter that hides the newest note must not select
        // a row the user cannot see.
        let shown = days(["2026-08-09"])
        #expect(
            JournalListView.initialSelection(days: shown, current: nil)
                == DateKey(raw: "2026-08-09")!
        )
    }
}

@Suite("Les miniatures d'une rangée")
@MainActor
struct JournalThumbnailsTests {
    @Test("deux miniatures au plus, le reste devient un nombre")
    func atmostTwoThenACount() {
        let sources = (1...5).map {
            JournalThumbnails.Source.vault(path: "pieces-jointes/2026-08-13-\($0).jpg")
        }
        let strip = JournalThumbnails.strip(of: sources)
        #expect(strip.shown.count == 2)
        #expect(strip.shown.first == .vault(path: "pieces-jointes/2026-08-13-1.jpg"))
        #expect(strip.extra == 3)
    }

    @Test("sous la limite, rien n'est laissé de côté")
    func belowTheLimitNothingIsLeftOut() {
        let strip = JournalThumbnails.strip(
            of: [.vault(path: "a.jpg"), .vault(path: "b.jpg")]
        )
        #expect(strip.shown.count == 2)
        #expect(strip.extra == 0)
        #expect(JournalThumbnails.strip(of: []).extra == 0)
    }

    @Test("sans coffre, aucun fichier n'est cherché")
    func withoutAVaultNothingIsLoaded() {
        #expect(
            JournalThumbnails.image(
                for: .vault(path: "x.jpg"), folder: nil, context: nil
            ) == nil
        )
    }
}
