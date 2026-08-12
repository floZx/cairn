import Testing
@testable import Cairn

@Suite("Markdown vers HTML")
struct MarkdownHTMLTests {
    @Test("les caractères réservés du HTML sont échappés")
    func escapesReservedCharacters() {
        #expect(MarkdownHTML.escape("a & b") == "a &amp; b")
        #expect(MarkdownHTML.escape("<script>") == "&lt;script&gt;")
        #expect(MarkdownHTML.escape("\"") == "&quot;")
        // L'esperluette d'abord, sinon &lt; devient &amp;lt;.
        #expect(MarkdownHTML.escape("&lt;") == "&amp;lt;")
    }

    @Test("chaque bloc du parseur a sa balise")
    func rendersEveryBlock() {
        #expect(MarkdownHTML.render("# Titre") == "<h1>Titre</h1>")
        #expect(MarkdownHTML.render("## Titre") == "<h2>Titre</h2>")
        #expect(MarkdownHTML.render("Bonjour.") == "<p>Bonjour.</p>")
        #expect(MarkdownHTML.render("> Cité") == "<blockquote>Cité</blockquote>")
    }

    @Test("les puces consécutives tiennent dans une seule liste")
    func groupsConsecutiveBullets() {
        let html = MarkdownHTML.render("- un\n- deux")
        #expect(html == "<ul><li>un</li><li>deux</li></ul>")
    }

    @Test("les listes numérotées gardent le numéro de l'auteur")
    func keepsTheAuthorsNumbering() {
        // Une liste qui commence à 3 est en général une erreur, mais la
        // renuméroter en douce est pire que la montrer.
        let html = MarkdownHTML.render("3. trois\n4. quatre")
        #expect(html == "<ol start=\"3\"><li>trois</li><li>quatre</li></ol>")
    }

    @Test("le gras, l'italique et le code passent en balises")
    func rendersInlineMarkup() {
        #expect(MarkdownHTML.render("un **gras**") == "<p>un <strong>gras</strong></p>")
        #expect(MarkdownHTML.render("un __gras__") == "<p>un <strong>gras</strong></p>")
        #expect(MarkdownHTML.render("un *penché*") == "<p>un <em>penché</em></p>")
        #expect(MarkdownHTML.render("un _penché_") == "<p>un <em>penché</em></p>")
        #expect(MarkdownHTML.render("du `code`") == "<p>du <code>code</code></p>")
    }

    @Test("un délimiteur solitaire reste un caractère de la note")
    func aloneDelimiterSurvives() {
        #expect(MarkdownHTML.render("3 * 4") == "<p>3 * 4</p>")
        #expect(MarkdownHTML.render("un *penché* et 3 * 4").contains("<em>penché</em>"))
    }

    @Test("le dièse d'un tag tombe, comme partout où une note se lit")
    func dropsTagHashes() {
        #expect(MarkdownHTML.render("Vu #Sam hier.") == "<p>Vu Sam hier.</p>")
        // `#2026` est une année, pas un tag.
        #expect(MarkdownHTML.render("En #2026.") == "<p>En #2026.</p>")
        #expect(
            MarkdownHTML.render("Vu #Sam.", hidingTagHashes: false)
                == "<p>Vu #Sam.</p>"
        )
    }

    @Test("le balisage ne peut pas injecter de HTML")
    func markupCannotInjectHTML() {
        #expect(
            MarkdownHTML.render("<b>gras</b>") == "<p>&lt;b&gt;gras&lt;/b&gt;</p>"
        )
        #expect(
            MarkdownHTML.render("# <img src=x>") == "<h1>&lt;img src=x&gt;</h1>"
        )
    }

    @Test("un texte vide ne produit rien")
    func emptyTextRendersNothing() {
        #expect(MarkdownHTML.render("") == "")
        #expect(MarkdownHTML.render("   \n  ") == "")
    }
}
