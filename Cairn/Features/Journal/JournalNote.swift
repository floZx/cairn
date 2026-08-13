import Foundation

/// One day's note, as read from disk.
///
/// A value, not a model: the file is the truth, and this is what one file says
/// at one moment. `tags` is derived at construction rather than stored — the
/// text is the only thing that ever needs writing back.
struct JournalNote: Identifiable, Equatable, Sendable {
    let date: DateKey
    let text: String
    /// False when the file could not be decoded. Such a note is still listed —
    /// an invisible note is a lost note — but the editor refuses it rather than
    /// offering to overwrite what it could not read.
    let isReadable: Bool
    let tags: Set<JournalTag>

    var id: DateKey { date }

    init(date: DateKey, text: String, isReadable: Bool = true) {
        self.date = date
        self.text = text
        self.isReadable = isReadable
        self.tags = isReadable ? JournalTagScanner.tags(in: text) : []
    }

    /// Whitespace only.
    ///
    /// The rule behind it: opening today's note and typing nothing must not
    /// leave an empty file in the vault, where Obsidian would list it for
    /// nothing. The store deletes such a file rather than writing it.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The note without its YAML front matter: what a reader is meant to see.
    ///
    /// Deliberately *not* a rule of `MarkdownParser`. That parser also renders
    /// the notes of an activity, which are a field in a database and never
    /// carry front matter — a `---` typed there is a separator someone meant to
    /// see, and a parser that swallowed it would be interpreting a text it has
    /// no business interpreting. Front matter is a fact about files in a vault,
    /// so the journal drops it on the way to the renderer rather than teaching
    /// every note in the app that `---` can be invisible.
    ///
    /// A static function on a `String` and not a property, because the pane
    /// renders the buffer being typed, which is not always `text`.
    ///
    /// The block only counts at the very top of the file, as it does for the
    /// tags: below the first line, `---` is a horizontal rule. An unterminated
    /// block loses only its opening `---` — what follows is almost certainly
    /// the note itself, and hiding it to the end of the file would lose it.
    ///
    /// That last rule is where this parts company with
    /// `JournalTagScanner.frontmatter`, on purpose: without a closing
    /// delimiter there is no block to read keys from, so it yields no tags,
    /// while here there is still a note to show. Change one and read the other.
    static func body(of text: String) -> String {
        var lines = text.components(separatedBy: .newlines)[...]
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return text
        }
        lines = lines.dropFirst()
        if let closing = lines.firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line == "---" || line == "..."
        }) {
            lines = lines[lines.index(after: closing)...]
        }
        return lines.joined(separator: "\n")
    }

    /// The first real line, for the list row.
    ///
    /// Front matter is skipped: `tags: [sam]` is metadata, and a list of rows
    /// all reading "---" says nothing about any of them.
    ///
    /// The line goes through the block parser on the way out, so a day whose
    /// note opens on a title or a bullet is announced by what it says rather
    /// than by how it was typed. One line goes in, so nothing is joined to it —
    /// the row stands for the day, it does not summarise the note.
    var summary: String {
        guard isReadable else { return "contenu illisible" }
        let first = Self.body(of: text)
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let spoken = MarkdownParser.blocks(from: first).first?.text
            ?? first.trimmingCharacters(in: .whitespaces)
        return String(spoken.prefix(160))
    }

    /// The pictures the note points at, in the order they were written.
    ///
    /// Derived from the text like `tags`, and through the parser rather than a
    /// second reading of it: what counts as an image in a note is a decision
    /// `MarkdownParser` already makes, and two answers to it would drift.
    var imagePaths: [String] {
        MarkdownParser.blocks(from: Self.body(of: text)).compactMap { block in
            if case let .image(path, _) = block { return path }
            return nil
        }
    }

    /// How every comparison in this type is made: case- and accent-blind, in
    /// French. `range(of:options:)` rather than folding both strings by hand,
    /// so the range it returns indexes the *original* text and the excerpt can
    /// be cut from it.
    private static let searchOptions: String.CompareOptions =
        [.caseInsensitive, .diacriticInsensitive]
    private static let locale = Locale(identifier: "fr_FR")

    func matches(query: String) -> Bool {
        Self.matches(text, query: query)
    }

    /// The same search over any text, so the day's activity notes are read by
    /// the rule that reads the day's own — one implementation, not two that
    /// drift.
    static func matches(_ text: String, query: String) -> Bool {
        range(of: query, in: text) != nil
    }

    /// Where a query lands in a text, case- and accent-blind, in French.
    ///
    /// `range(of:options:)` rather than folding both strings by hand, so the
    /// range it returns indexes the *original* text and an excerpt can be cut
    /// from it. An empty query matches at the start, which is what makes an
    /// unfiltered list keep everything.
    static func range(
        of query: String, in text: String
    ) -> Range<String.Index>? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return text.startIndex..<text.startIndex }
        return text.range(
            of: trimmed, options: searchOptions, range: nil, locale: locale
        )
    }

    /// The passage around the match, for the list row.
    ///
    /// A row that says only "mardi 11 août" tells the reader nothing about why
    /// the search kept it — showing the first line instead would be worse
    /// still, since it is usually not where the match is.
    func excerpt(matching query: String) -> String? {
        Self.excerpt(of: text, matching: query)
    }

    /// The same passage-finding over any text — see `matches(_:query:)`.
    static func excerpt(of text: String, matching query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let match = range(of: trimmed, in: text)
        else { return nil }

        let before = 40
        let after = 80
        let start = text.index(
            match.lowerBound, offsetBy: -before, limitedBy: text.startIndex
        ) ?? text.startIndex
        let end = text.index(
            match.upperBound, offsetBy: after, limitedBy: text.endIndex
        ) ?? text.endIndex

        // Newlines become spaces: the row is one line high, and a passage cut
        // across a paragraph break would otherwise render as a gap.
        let body = text[start..<end]
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let head = start == text.startIndex ? "" : "…"
        let tail = end == text.endIndex ? "" : "…"
        return head + body + tail
    }

    /// Every ticked tag, not any of them: a note carries several, so the point
    /// of ticking the second one is to narrow. Sports work the other way round
    /// because an activity has exactly one.
    func has(_ required: Set<JournalTag>) -> Bool {
        required.isSubset(of: tags)
    }

    /// Search text and ticked tags together, newest first.
    static func filter(
        _ notes: [JournalNote], query: String, tags: Set<JournalTag>
    ) -> [JournalNote] {
        notes
            .filter { $0.has(tags) && $0.matches(query: query) }
            .sorted { $0.date > $1.date }
    }
}
