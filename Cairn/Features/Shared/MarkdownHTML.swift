import Foundation

/// A note, as HTML — for the exported book.
///
/// Built on the screen's parser rather than a second one: `MarkdownParser`
/// decides what a heading, a bullet and a quotation are, and a note has to come
/// out the same shape in the book as in the pane. Only what the screen leaves
/// to `Text` — the inline markup — and what a file needs and a view never does
/// — escaping — are this type's own business.
enum MarkdownHTML {
    /// The characters that would otherwise be read as markup.
    ///
    /// The ampersand first: escaping it after `<` would turn the `&lt;` just
    /// produced into `&amp;lt;`, and every note with a bracket in it would come
    /// out of the book showing its own escaping.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// - Parameter hidingTagHashes: on by default. A note is *read* here, and
    ///   the hash is syntax — the same call the panes make.
    static func render(_ markdown: String, hidingTagHashes: Bool = true) -> String {
        var html = ""
        // Consecutive bullets belong to one list: a `<ul>` per line would give
        // each item its own block of air.
        var openList: String?

        func closeList() {
            if let openList { html += "</\(openList)>" }
            openList = nil
        }

        for block in MarkdownParser.blocks(from: markdown) {
            let text = inline(block.text, hidingTagHashes: hidingTagHashes)
            switch block {
            case let .heading(level, _):
                closeList()
                html += "<h\(level)>\(text)</h\(level)>"
            case .paragraph:
                closeList()
                html += "<p>\(text)</p>"
            case .image:
                // The alt text for now: the book cannot link to a file in the
                // vault, and embedding the picture is the next task's work.
                closeList()
                html += "<p>\(text)</p>"
            case .quote:
                closeList()
                html += "<blockquote>\(text)</blockquote>"
            case .bullet:
                if openList != "ul" {
                    closeList()
                    html += "<ul>"
                    openList = "ul"
                }
                html += "<li>\(text)</li>"
            case let .numbered(number, _):
                if openList != "ol" {
                    closeList()
                    // The author's own number, for the reason `MarkdownBlock`
                    // states: a list starting at 3 is usually a mistake, and
                    // renumbering it silently is worse than showing it.
                    html += "<ol start=\"\(number)\">"
                    openList = "ol"
                }
                html += "<li>\(text)</li>"
            }
        }
        closeList()
        return html
    }

    /// Inline markup, over text that is escaped first: everything below then
    /// works on a string where no `<` can be the author's, so a delimiter can
    /// become a tag without a second thought.
    ///
    /// The two-character forms go first — `**` before `*` — or the first pass
    /// would eat half of each pair and leave the other half stranded.
    private static func inline(_ text: String, hidingTagHashes: Bool) -> String {
        var result = escape(text)
        for (delimiter, tag) in [
            ("**", "strong"), ("__", "strong"), ("*", "em"), ("_", "em"),
            ("`", "code"),
        ] {
            result = spans(in: result, delimiter: delimiter, tag: tag)
        }
        return hidingTagHashes ? withoutTagHashes(result) : result
    }

    /// Pairs of delimiters into tags, left to right.
    ///
    /// An unmatched delimiter is left exactly where it was: a lone asterisk in
    /// a note is an asterisk, and a note is not a document — swallowing it
    /// would lose a character the writer typed on purpose.
    private static func spans(
        in text: String, delimiter: String, tag: String
    ) -> String {
        let parts = text.components(separatedBy: delimiter)
        guard parts.count > 2 else { return text }

        var result = parts[0]
        var index = 1
        while index < parts.count {
            // A span needs both halves: an opening delimiter with nothing
            // closing it keeps its characters.
            if index + 1 < parts.count {
                result += "<\(tag)>\(parts[index])</\(tag)>"
                result += parts[index + 1]
                index += 2
            } else {
                result += delimiter + parts[index]
                index += 1
            }
        }
        return result
    }

    /// Drops the `#` of every tag, by `JournalTagScanner`'s rules reached
    /// through `JournalTag`: the hash opens the run, `# ` is a heading — and
    /// never reaches here, the parser having taken it — and `#2026` is a year.
    private static func withoutTagHashes(_ text: String) -> String {
        var result = ""
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "#", previous == nil || previous!.isWhitespace else {
                result.append(character)
                previous = character
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            while end < text.endIndex, JournalTag.isAllowed(text[end]) {
                end = text.index(after: end)
            }
            let name = String(text[text.index(after: index)..<end])
            result += JournalTag(name: name) != nil ? name : "#" + name
            previous = name.last ?? "#"
            index = end
        }
        return result
    }
}
