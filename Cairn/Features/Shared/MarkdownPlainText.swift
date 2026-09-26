import Foundation

/// A note as plain text, for a service that shows its characters as they are.
///
/// Garmin Connect's description is a bare text field: « **Seuil** » arrived
/// there with its asterisks. Read the way the panes read it — the same parser
/// for blocks, `AttributedString` for bold, italic, code and links, the tags
/// without their `#` — and written back as lines of prose: a heading is a
/// line, a list keeps a « • », a picture is left out. A mention loses its
/// `@` as the notes did once already (`StoreMaintenance.withoutMentionSigns`),
/// and the underscores that join a handle's words: « @nom_d_une_personne »
/// goes out as « nom d une personne ».
enum MarkdownPlainText {
    static func render(_ markdown: String) -> String {
        var result = ""
        var previousWasItem = false

        for block in MarkdownParser.blocks(from: markdown) {
            let text = inline(block.text)
            let line: String
            let isItem: Bool
            switch block {
            case .heading, .paragraph, .quote:
                line = text
                isItem = false
            case .bullet:
                line = "• " + text
                isItem = true
            case let .numbered(number, _):
                line = "\(number). " + text
                isItem = true
            case .image:
                continue
            }
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            // One line between the items of a list, a blank one between
            // everything else — as the note is laid out on screen.
            if !result.isEmpty { result += isItem && previousWasItem ? "\n" : "\n\n" }
            result += line
            previousWasItem = isItem
        }
        return result
    }

    private static func inline(_ text: String) -> String {
        guard let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return text }
        return withoutMentions(String(MarkdownText.withoutTagHashes(attributed).characters))
    }

    /// The maintenance's rule for what a mention is — a `@` opening a name,
    /// not an address's nor a pace's « @ 4:15/km » — with the handle's
    /// underscores turned back into spaces.
    private static let mention = try! NSRegularExpression(
        pattern: #"(?<![\w.])@(\p{L}[\p{L}\p{N}_-]*)"#
    )

    static func withoutMentions(_ text: String) -> String {
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in mention.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += source.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "_", with: " ")
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }
}
