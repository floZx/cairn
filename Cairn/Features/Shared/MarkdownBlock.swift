import Foundation

/// One block of a note, once its Markdown has been read.
///
/// SwiftUI's `Text` understands Markdown, but only the inline half of it —
/// bold, italic, code, links. Headings, bullets and quotes come back as plain
/// text with the marker still in front, which is the half a logbook actually
/// uses. Blocks are split here so each can be laid out for what it is; the
/// inline formatting inside them is still left to `Text`.
enum MarkdownBlock: Equatable, Identifiable, Sendable {
    /// Level 1 to 3; deeper headings in a note are indistinguishable anyway.
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    /// The number is the author's, not a running count: a list starting at 3 is
    /// usually a mistake, but renumbering it silently is worse than showing it.
    case numbered(number: Int, text: String)
    case quote(String)
    /// A picture on a line of its own. Only there: an image inside a sentence
    /// is a sentence, and this parser recognises nothing it was not asked to.
    case image(path: String, alt: String)

    /// What the block says, without the marker that made it one.
    ///
    /// For anywhere a note has to be shown as a line of prose — a list row —
    /// rather than laid out block by block: there, a leading `#` or `- ` is
    /// how the line was typed, not what it says.
    var text: String {
        switch self {
        case let .heading(_, text): text
        case let .paragraph(text): text
        case let .bullet(text): text
        case let .numbered(_, text): text
        case let .quote(text): text
        // The alt text: what a renderer with no picture to show must write.
        case let .image(_, alt): alt
        }
    }

    var id: String {
        switch self {
        case let .heading(level, text): "h\(level)-\(text)"
        case let .paragraph(text): "p-\(text)"
        case let .bullet(text): "u-\(text)"
        case let .numbered(number, text): "o\(number)-\(text)"
        case let .quote(text): "q-\(text)"
        case let .image(path, _): "img-\(path)"
        }
    }
}

enum MarkdownParser {
    /// Splits a note into blocks.
    ///
    /// Deliberately small: a note is not a document, and every construct here is
    /// one people type without thinking about Markdown at all — a dash for a
    /// list, a `#` for a title, a `>` for a quotation. Anything else falls
    /// through to a paragraph rather than being mangled.
    ///
    /// Consecutive non-empty lines are joined into one paragraph, as Markdown
    /// does: a note wrapped by hand in the editor should not come out as a
    /// column of one-line paragraphs.
    static func blocks(from markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = heading(in: line) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if let bullet = bullet(in: line) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }
            if let numbered = numbered(in: line) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }
            if let image = image(in: line) {
                flushParagraph()
                blocks.append(image)
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(
                    .quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                )
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        return blocks
    }

    private static func heading(in line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty else { return nil }
        // A space is required after the hashes, as in Markdown proper: "#3 au
        // classement" is a note about a placing, not a heading.
        let rest = line.dropFirst(hashes.count)
        guard rest.hasPrefix(" ") else { return nil }
        return .heading(
            level: min(hashes.count, 3),
            text: rest.trimmingCharacters(in: .whitespaces)
        )
    }

    /// `![alt](chemin)` and nothing else on the line.
    ///
    /// Deliberately strict: a bracket left inside the path, or anything before
    /// or after, means this was never one picture — and a paragraph showing
    /// its own markup is a better answer than an image drawn from a guess.
    private static func image(in line: String) -> MarkdownBlock? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let altEnd = line.firstIndex(of: "]"),
              line.index(after: altEnd) < line.endIndex,
              line[line.index(after: altEnd)] == "("
        else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd])
        let path = String(
            line[line.index(altEnd, offsetBy: 2)..<line.index(before: line.endIndex)]
        )
        guard !path.isEmpty, !path.contains("]"), !path.contains("(") else {
            return nil
        }
        return .image(path: path, alt: alt)
    }

    private static func bullet(in line: String) -> MarkdownBlock? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return .bullet(
                String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            )
        }
        return nil
    }

    private static func numbered(in line: String) -> MarkdownBlock? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return .numbered(
            number: number,
            text: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        )
    }
}
