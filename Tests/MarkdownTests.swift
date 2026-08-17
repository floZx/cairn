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
        // `JournalFileNote.body(of:)`, on the way to the renderer.
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
    private func rendered(_ text: String) -> String {
        String(MarkdownText.withoutTagHashes(AttributedString(text)).characters)
    }

    @Test("un tag perd son dièse")
    func aTagLosesItsHash() {
        #expect(
            rendered("Promenade avec #Sam pendant midi.")
                == "Promenade avec Sam pendant midi."
        )
    }

    @Test("plusieurs tags sur une ligne sont tous traités")
    func severalTagsOnOneLine() {
        #expect(
            rendered("Sortie #vélo puis #repos, enfin.")
                == "Sortie vélo puis repos, enfin."
        )
    }

    @Test("un tag imbriqué garde ses barres obliques")
    func aNestedTagKeepsItsSlashes() {
        #expect(rendered("#projet/cairn avance") == "projet/cairn avance")
    }

    @Test("un tag entièrement numérique n'en est pas un")
    func aNumericTagIsLeftAlone() {
        #expect(rendered("Objectif #2026 tenu.") == "Objectif #2026 tenu.")
    }

    @Test("un dièse collé à un mot est laissé tel quel")
    func aHashInsideAWordIsLeftAlone() {
        #expect(rendered("code#4 du portail") == "code#4 du portail")
    }

    @Test("un dièse suivi d'une espace est laissé tel quel")
    func aLoneHashIsLeftAlone() {
        #expect(rendered("# pas un tag") == "# pas un tag")
    }

    @Test("un texte sans tag traverse sans changer")
    func textWithoutTagsIsUnchanged() {
        let source = "Rien à signaler aujourd'hui."
        #expect(rendered(source) == source)
    }

    @Test("le rendu ne pose aucune couleur")
    func nothingIsColoured() {
        // Tried and taken back out on 11 August 2026: the accent colour made a
        // tag look like something one could click, in a note where it is not.
        let result = MarkdownText.withoutTagHashes(AttributedString("Vu #Sam hier."))
        #expect(result.runs.allSatisfy { $0.foregroundColor == nil })
    }
}

@Suite("Les images d'une note")
struct MarkdownImageTests {
    @Test("une ligne qui n'est qu'une image devient un bloc image")
    func alineThatIsOnlyAnImageBecomesAnImageBlock() {
        #expect(
            MarkdownParser.blocks(from: "![](pieces-jointes/2026-08-13-1.jpg)")
                == [.image(path: "pieces-jointes/2026-08-13-1.jpg", alt: "")]
        )
        #expect(
            MarkdownParser.blocks(from: "![Le sommet](x.png)")
                == [.image(path: "x.png", alt: "Le sommet")]
        )
    }

    @Test("une image au milieu d'une phrase reste du texte")
    func animageInsideASentenceStaysText() {
        // La même retenue que le reste du parseur : il ne reconnaît que ce que
        // quelqu'un tape sans penser à Markdown.
        #expect(
            MarkdownParser.blocks(from: "voir ![](x.jpg) ici")
                == [.paragraph("voir ![](x.jpg) ici")]
        )
        // Un lien sans chemin n'est pas une image.
        #expect(MarkdownParser.blocks(from: "![]()") == [.paragraph("![]()")])
    }

    @Test("le texte d'un bloc image est son texte de remplacement")
    func theimageBlockTextIsItsAlt() {
        #expect(
            MarkdownBlock.image(path: "x.jpg", alt: "Le sommet").text == "Le sommet"
        )
    }
}
