import Testing
import SwiftUI
@testable import Cairn

@Suite("Markdown des notes")
struct MarkdownTests {
    @Test("les lignes consécutives forment un seul paragraphe")
    func joinsWrappedLines() {
        // A note wrapped by hand in the editor must not come out as a column of
        // one-line paragraphs.
        #expect(
            MarkdownParser.blocks(from: "Sortie facile\nsur le plateau.")
                == [.paragraph("Sortie facile sur le plateau.")]
        )
        // A blank line is what separates two of them.
        #expect(
            MarkdownParser.blocks(from: "Un.\n\nDeux.")
                == [.paragraph("Un."), .paragraph("Deux.")]
        )
    }

    @Test("titres, listes et citations sont reconnus")
    func recognisesTheBlocks() {
        let note = """
        # Compte rendu
        ## Sensations
        - jambes lourdes
        * vent de face
        1. premier tour
        2) second tour
        > à refaire au frais
        """
        #expect(MarkdownParser.blocks(from: note) == [
            .heading(level: 1, text: "Compte rendu"),
            .heading(level: 2, text: "Sensations"),
            .bullet("jambes lourdes"),
            .bullet("vent de face"),
            .numbered(number: 1, text: "premier tour"),
            .numbered(number: 2, text: "second tour"),
            .quote("à refaire au frais"),
        ])
    }

    @Test("un dièse sans espace n'est pas un titre")
    func aHashWithoutASpaceIsNotAHeading() {
        // "#3 au classement" is a note about a placing. Markdown requires the
        // space, and so does anyone writing that sentence.
        #expect(
            MarkdownParser.blocks(from: "#3 au classement")
                == [.paragraph("#3 au classement")]
        )
    }

    @Test("un tiret au fil du texte ne devient pas une puce")
    func aDashInProseIsNotABullet() {
        // The marker has to open the line: "10-15 km/h de vent" is prose.
        #expect(
            MarkdownParser.blocks(from: "10-15 km/h de vent")
                == [.paragraph("10-15 km/h de vent")]
        )
    }

    @Test("les titres profonds sont ramenés à trois niveaux")
    func headingsAreCapped() {
        // Below the third level a heading is indistinguishable from the one
        // above it, so pretending otherwise buys nothing.
        #expect(
            MarkdownParser.blocks(from: "##### Détail")
                == [.heading(level: 3, text: "Détail")]
        )
    }

    @Test("une note vide ne produit aucun bloc")
    func emptyNotesProduceNothing() {
        #expect(MarkdownParser.blocks(from: "").isEmpty)
        #expect(MarkdownParser.blocks(from: "\n  \n\n").isEmpty)
    }

    @Test("le parseur ne mange pas le frontmatter, c'est à l'appelant de le faire")
    func theParserLeavesFrontMatterAlone() {
        // Deliberate: this parser also renders the notes of an activity, which
        // are a field in a database and never carry front matter. A `---` typed
        // there is a separator someone meant to see. Only the journal, whose
        // notes are files in an Obsidian vault, drops the block — through
        // `JournalNote.body(of:)`, on the way to the renderer.
        #expect(
            MarkdownParser.blocks(from: "---\ntags: [sam]\n---\nPromenade.")
                == [.paragraph("--- tags: [sam] --- Promenade.")]
        )
    }

    @Test("une numérotation qui ne part pas de un est respectée")
    func keepsTheAuthorsNumbering() {
        // A list starting at 3 is usually a mistake, but renumbering it in
        // silence is worse than showing what was typed.
        #expect(
            MarkdownParser.blocks(from: "3. troisième")
                == [.numbered(number: 3, text: "troisième")]
        )
    }
}

@Suite("Tags rendus dans une note")
@MainActor
struct MarkdownTaggedTests {
    private func tagged(_ text: String) -> AttributedString {
        MarkdownText.tagged(AttributedString(text))
    }

    private func plain(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    /// The colour the runs are checked against — read from the same place the
    /// renderer sets it, so a change of colour never turns into a test failure.
    private let accent = Color.accentColor

    @Test("un tag perd son dièse et prend la couleur d'accent")
    func aTagLosesItsHashAndTakesTheColour() {
        let result = tagged("Promenade avec #Sam pendant midi.")
        #expect(plain(result) == "Promenade avec Sam pendant midi.")
        let coloured = result.runs
            .filter { $0.foregroundColor == accent }
            .map { String(result[$0.range].characters) }
        #expect(coloured == ["Sam"])
    }

    @Test("le texte autour du tag n'est pas coloré")
    func onlyTheTagIsColoured() {
        let result = tagged("Vu #Sam hier.")
        let uncoloured = result.runs
            .filter { $0.foregroundColor == nil }
            .map { String(result[$0.range].characters) }
            .joined()
        #expect(uncoloured == "Vu  hier.")
    }

    @Test("plusieurs tags sur une ligne sont tous traités")
    func severalTagsOnOneLine() {
        let result = tagged("Sortie #vélo puis #repos, enfin.")
        #expect(plain(result) == "Sortie vélo puis repos, enfin.")
        let coloured = result.runs
            .filter { $0.foregroundColor == accent }
            .map { String(result[$0.range].characters) }
        #expect(coloured == ["vélo", "repos"])
    }

    @Test("un tag imbriqué garde ses barres obliques")
    func aNestedTagKeepsItsSlashes() {
        let result = tagged("#projet/cairn avance")
        #expect(plain(result) == "projet/cairn avance")
    }

    @Test("un tag entièrement numérique n'en est pas un")
    func aNumericTagIsLeftAlone() {
        let result = tagged("Objectif #2026 tenu.")
        #expect(plain(result) == "Objectif #2026 tenu.")
        #expect(result.runs.allSatisfy { $0.foregroundColor == nil })
    }

    @Test("un dièse collé à un mot est laissé tel quel")
    func aHashInsideAWordIsLeftAlone() {
        let result = tagged("code#4 du portail")
        #expect(plain(result) == "code#4 du portail")
    }

    @Test("un dièse suivi d'une espace est laissé tel quel")
    func aLoneHashIsLeftAlone() {
        let result = tagged("# pas un tag")
        #expect(plain(result) == "# pas un tag")
    }

    @Test("un texte sans tag traverse sans changer")
    func textWithoutTagsIsUnchanged() {
        let source = "Rien à signaler aujourd'hui."
        #expect(plain(tagged(source)) == source)
    }
}
