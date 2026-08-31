import AppKit
import SwiftUI

/// A note, rendered.
///
/// Blocks come from `MarkdownParser`; the inline formatting inside each one is
/// left to `Text`, which already understands bold, italic, code and links.
struct MarkdownText: View {
    let markdown: String

    /// Point size for body text, headings derived from it. Nil keeps the
    /// system text styles, which is what an activity note uses — those sit in
    /// a pane of figures and should read like the rest of it. A journal note
    /// fills its pane and is read for minutes at a time, so it asks for more.
    var baseSize: CGFloat?

    /// Whether a tag's `#` is dropped from what is displayed.
    ///
    /// On wherever a note is *read*, journal and activity alike. Off by
    /// default: it removes characters from the text, which should be asked for
    /// rather than inherited.
    var hidesTagHashes = false

    /// The folder a picture's relative path resolves against — the vault, for
    /// a journal note. Nil where there is none: an activity's note has no
    /// attachments, and pretending otherwise would draw an empty frame under
    /// every line that happens to look like a link.
    var attachmentsBase: URL?

    private var blocks: [MarkdownBlock] { MarkdownParser.blocks(from: markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Un bloc, une popover : elle s'ancre sur ce qu'on a cliqué. Posée
            // sur la note entière, elle s'ouvrait sous le dernier paragraphe,
            // à des centimètres du mot. Signalé.
            ForEach(blocks) { block in
                BlocDeNote { vue(pour: block) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func vue(pour block: MarkdownBlock) -> some View {
        switch block {
                case let .heading(level, text):
            inline(text)
                .font(headingFont(level))
                // Air above a heading and not below it: the gap belongs to what
                // the heading separates from, not to what it introduces.
                .padding(.top, block == blocks.first ? 0 : 6)
        case let .paragraph(text):
            sized(inline(text))
        case let .bullet(text):
            marker("•", text)
        case let .numbered(number, text):
            marker("\(number).", text)
        case let .image(path, alt):
            image(path: path, alt: alt)
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                // A rule rather than an indent: an indent alone is
                // indistinguishable from a wrapped line.
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 2)
                sized(inline(text))
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The picture, or its name.
    ///
    /// A missing file is not worth a broken frame: in a vault synced by
    /// iCloud, a picture that has not come down yet is not a picture that is
    /// gone, and nothing here can tell the two apart. Its name says which one
    /// is being waited for.
    @ViewBuilder
    private func image(path: String, alt: String) -> some View {
        if let base = attachmentsBase,
           let picture = NSImage(contentsOf: base.appending(path: path)) {
            Image(nsImage: picture)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            sized(Text(alt.isEmpty ? path : alt))
                .foregroundStyle(.secondary)
        }
    }

    private func marker(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            sized(Text(symbol))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                // A gutter, so the text of every item starts at the same place
                // whether the marker is "•" or "10.".
                .frame(width: 22, alignment: .trailing)
            sized(inline(text))
        }
    }

    /// Applies the body size, or leaves the text to inherit.
    ///
    /// Deliberately not `.font(baseSize.map { … })`: `.font(nil)` *resets* the
    /// environment font rather than leaving it alone, which would change what
    /// an activity note inherits from the pane around it.
    @ViewBuilder
    private func sized(_ text: Text) -> some View {
        if let baseSize {
            text.font(.system(size: baseSize))
        } else {
            text
        }
    }

    /// Headings step above the body rather than sitting at fixed text styles.
    ///
    /// With a base size set, `.subheadline` for a level 3 would land *below*
    /// the paragraphs it introduces — a heading smaller than its own text.
    private func headingFont(_ level: Int) -> Font {
        guard let baseSize else {
            return switch level {
            case 1: .title3.bold()
            case 2: .headline
            default: .subheadline.bold()
            }
        }
        return switch level {
        case 1: .system(size: baseSize + 5, weight: .bold)
        case 2: .system(size: baseSize + 2, weight: .semibold)
        default: .system(size: baseSize, weight: .bold)
        }
    }

    private func inline(_ text: String) -> Text {
        Self.inline(text, hidingTagHashes: hidesTagHashes)
    }

    /// Inline Markdown, or the raw text when it will not parse.
    ///
    /// Falling back rather than throwing: a stray bracket in a note must show
    /// the note, not an error — and `AttributedString` refuses more input than
    /// one would expect.
    static func inline(_ text: String, hidingTagHashes: Bool = false) -> Text {
        guard let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            // The raw text, hashes and all: the fallback's job is to show the
            // note rather than an error, and picking tags out of a string
            // Markdown could not parse would be guessing twice.
            return Text(text)
        }
        let sansDièses = hidingTagHashes ? withoutTagHashes(attributed) : attributed
        return Text(withHighlightedMentions(sansDièses))
    }

    /// Colore les `@pseudo` sans les toucher autrement.
    ///
    /// Le `@` reste, à la différence du `#` des tags : « @sam » se lit comme un
    /// nom là où « #trail » se lit comme un mot, et retirer l'arobase donnerait
    /// « sam » au milieu d'une phrase, indistinguable du reste.
    ///
    /// La couleur seule, ni fond ni gras : dans une note qui cite trois
    /// personnes, trois pastilles feraient une décoration là où trois mots
    /// colorés se lisent encore comme une phrase.
    ///
    /// Les règles de reconnaissance sont celles de `PersonScanner`, atteintes
    /// par `PersonHandle` plutôt que recopiées — une seconde copie dériverait
    /// de la liste que l'écran People affiche vraiment.
    static func withHighlightedMentions(_ attributed: AttributedString) -> AttributedString {
        var resultat = attributed
        var trouves: [Range<AttributedString.Index>] = []
        let caracteres = resultat.characters
        var precedent: Character?
        var index = caracteres.startIndex

        while index < caracteres.endIndex {
            let caractere = caracteres[index]
            defer {
                precedent = caractere
                index = caracteres.index(after: index)
            }
            guard caractere == "@" else { continue }
            guard precedent == nil || precedent!.isWhitespace
                || "([{«\"'-–—*>".contains(precedent!)
            else { continue }

            let debut = caracteres.index(after: index)
            var fin = debut
            while fin < caracteres.endIndex, PersonHandle.isAllowed(caracteres[fin]) {
                fin = caracteres.index(after: fin)
            }
            guard PersonHandle(name: String(caracteres[debut..<fin])) != nil else { continue }
            trouves.append(index..<fin)
        }

        for citation in trouves {
            resultat[citation].foregroundColor = .accentColor
            // Un lien, parce que c'est la seule façon dont un `Text` de SwiftUI
            // rend une plage cliquable : il n'y a pas de geste par plage de
            // texte, et le survol n'en a pas non plus. Voir `lien(pour:)` pour
            // ce que l'adresse transporte.
            let ecrit = String(resultat[citation].characters.dropFirst())
            if let handle = PersonHandle(name: ecrit) {
                resultat[citation].link = lien(pour: handle)
            }
        }
        return resultat
    }

    /// L'adresse d'une mention, qu'`openURL` reconnaîtra.
    ///
    /// Elle transporte le pseudo **tel qu'il est écrit**, pas sa clé repliée :
    /// `PersonHandle` sait passer de l'un à l'autre, et la fiche a besoin des
    /// deux — la clé pour retrouver la personne, l'orthographe pour la nommer.
    ///
    /// Un schéma à nous, et aucune déclaration dans `Info.plist` : rien ici ne
    /// doit pouvoir être ouvert de l'extérieur, ces adresses ne vivent que le
    /// temps d'un clic dans une note.
    static func lien(pour handle: PersonHandle) -> URL? {
        handle.name
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)
            .flatMap { URL(string: "\(schemaDesMentions):\($0)") }
    }

    /// La personne qu'une adresse désigne, ou nil quand ce n'en est pas une.
    static func mention(dans url: URL) -> PersonHandle? {
        guard url.scheme == schemaDesMentions else { return nil }
        let corps = url.absoluteString.dropFirst(schemaDesMentions.count + 1)
        guard let ecrit = corps.removingPercentEncoding else { return nil }
        return PersonHandle(name: ecrit)
    }

    private static let schemaDesMentions = "cairn-personne" 

    /// Drops the `#` from every tag.
    ///
    /// The hash is syntax, not reading matter: it is what Obsidian needs in the
    /// file and what the editor still shows, but on the page it says nothing —
    /// the same reason the sidebar and the chips lost theirs.
    ///
    /// The recognition rules are `JournalTagScanner.inline`'s, reached through
    /// `JournalTag.isAllowed` and `JournalTag.init?(name:)` rather than copied:
    /// a `#` opening the run, the allowed characters, and the two exclusions
    /// (`# ` is a heading, `#2026` is a year). A second copy of those rules
    /// would drift from the tags the sidebar actually lists.
    static func withoutTagHashes(_ attributed: AttributedString) -> AttributedString {
        var result = attributed
        var found: [Range<AttributedString.Index>] = []
        let characters = result.characters
        var previous: Character?
        var index = characters.startIndex

        while index < characters.endIndex {
            let character = characters[index]
            defer {
                previous = character
                index = characters.index(after: index)
            }
            guard character == "#", previous == nil || previous!.isWhitespace
            else { continue }

            let nameStart = characters.index(after: index)
            var end = nameStart
            while end < characters.endIndex, JournalTag.isAllowed(characters[end]) {
                end = characters.index(after: end)
            }
            guard JournalTag(name: String(characters[nameStart..<end])) != nil
            else { continue }
            found.append(index..<nameStart)
        }

        // Back to front: removing a hash shifts everything after it, so the
        // ranges still to come must all lie before the one being edited.
        for hash in found.reversed() {
            result.removeSubrange(hash)
        }
        return result
    }
}


/// Un bloc de note, avec la fiche d'une personne citée ancrée sur lui.
///
/// Le bloc et non la note : une popover posée sur la note entière s'ouvrait
/// sous son dernier paragraphe, à des centimètres du mot cliqué. Ancrée ici,
/// elle sort de la ligne qu'on lisait. Faute de savoir où un *mot* est dessiné
/// — SwiftUI ne le dit pas — c'est le plus près qu'on puisse arriver sans
/// réécrire le rendu du texte.
private struct BlocDeNote<Contenu: View>: View {
    @ViewBuilder var contenu: Contenu

    /// Optionnel : `MarkdownText` sert aussi hors de l'application montée —
    /// aperçus, essais — où personne n'a posé d'environnement.
    @Environment(AppEnvironment.self) private var app: AppEnvironment?
    @State private var personneOuverte: PersonHandle?

    var body: some View {
        contenu
            // Les liens ordinaires d'une note gardent leur sens : seule une
            // adresse de mention est détournée, le reste part au navigateur.
            .environment(\.openURL, OpenURLAction { url in
                guard let handle = MarkdownText.mention(dans: url) else {
                    return .systemAction
                }
                ouvrir(handle)
                return .handled
            })
            .popover(item: $personneOuverte) { handle in
                PersonPopoverCard(handle: handle)
            }
    }

    /// Ouvre la fiche, en demandant d'abord la clé du journal s'il est fermé.
    ///
    /// Une fiche est de la matière du journal — c'est ce qu'on a écrit sur
    /// quelqu'un — et une note de sortie qui cite `@Sam` se lit, elle, sans
    /// verrou. Sans ce passage, un clic depuis là ouvrirait par la fenêtre ce
    /// que la porte protège.
    private func ouvrir(_ handle: PersonHandle) {
        guard let verrou = app?.journalLock, !verrou.estOuvert else {
            personneOuverte = handle
            return
        }
        Task {
            await verrou.ouvrir()
            if verrou.estOuvert { personneOuverte = handle }
        }
    }
}
