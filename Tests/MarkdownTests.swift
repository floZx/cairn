import Testing
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
