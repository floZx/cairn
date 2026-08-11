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

    /// The first real line, for the list row.
    ///
    /// Front matter is skipped: `tags: [sam]` is metadata, and a list of rows
    /// all reading "---" says nothing about any of them.
    var summary: String {
        guard isReadable else { return "contenu illisible" }
        var lines = text.components(separatedBy: .newlines)[...]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            if let closing = lines.firstIndex(where: {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return line == "---" || line == "..."
            }) {
                lines = lines[lines.index(after: closing)...]
            }
        }
        let first = lines.first {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        } ?? ""
        return String(first.trimmingCharacters(in: .whitespaces).prefix(160))
    }

    /// How every comparison in this type is made: case- and accent-blind, in
    /// French. `range(of:options:)` rather than folding both strings by hand,
    /// so the range it returns indexes the *original* text and the excerpt can
    /// be cut from it.
    private static let searchOptions: String.CompareOptions =
        [.caseInsensitive, .diacriticInsensitive]
    private static let locale = Locale(identifier: "fr_FR")

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return text.range(
            of: trimmed, options: Self.searchOptions, range: nil,
            locale: Self.locale
        ) != nil
    }

    /// The passage around the match, for the list row.
    ///
    /// A row that says only "mardi 11 août" tells the reader nothing about why
    /// the search kept it — showing the first line instead would be worse
    /// still, since it is usually not where the match is.
    func excerpt(matching query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let match = text.range(
                  of: trimmed, options: Self.searchOptions, range: nil,
                  locale: Self.locale
              )
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
