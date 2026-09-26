import Foundation

/// A note as plain text, for a service that shows its characters as they are.
///
/// Garmin Connect's description is a bare text field: « **Seuil** » arrived
/// there with its asterisks. Read the way the panes read it — the same parser
/// for blocks, `AttributedString` for bold, italic, code and links, the tags
/// without their `#` — and written back as lines of prose: a heading is a
/// line, a list keeps a « • », a picture is left out.
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
        return String(MarkdownText.withoutTagHashes(attributed).characters)
    }
}
