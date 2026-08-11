import Foundation

/// One Obsidian tag, without its `#`.
///
/// A validated value rather than a bare `String`: the two rules that decide
/// what is a tag — the allowed characters, and "not all digits" — belong
/// with the type, not with each place that happens to read one.
struct JournalTag: Hashable, Comparable, Sendable, Identifiable {
    let name: String

    /// The characters Obsidian allows in a tag. Everything else ends it.
    ///
    /// Checked per `Character` (grapheme cluster) rather than with a
    /// `CharacterSet` of Unicode scalars: `CharacterSet.alphanumerics`
    /// matches a precomposed accented letter like `é` (U+00E9) but not the
    /// same letter written as `e` followed by a combining acute accent
    /// (U+0301) — two representations of what a person reading the text
    /// sees as one identical character. Working at the `Character` level
    /// treats both the same, so tag recognition doesn't depend on which
    /// normalisation form the source file happens to be in.
    static func isAllowed(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
            || character == "-" || character == "/"
    }

    /// - Returns: nil when this is not a tag Obsidian would recognise.
    init?(name: String) {
        // A trailing slash is a tag being typed, not a level: `#projet/`
        // means `#projet`.
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(Self.isAllowed),
              // Obsidian's own rule: a tag needs at least one character that
              // is not a digit, so `#2026` stays a year.
              trimmed.contains(where: { !$0.isNumber && $0 != "/" })
        else { return nil }
        self.name = trimmed
    }

    var id: String { name }

    var displayName: String { "#\(name)" }

    /// `projet/cairn/journal` also belongs to `projet/cairn` and to `projet`.
    /// Without this, ticking a parent in the sidebar would show nothing.
    var ancestors: [JournalTag] {
        let parts = name.split(separator: "/")
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).compactMap { depth in
            JournalTag(name: parts.prefix(depth).joined(separator: "/"))
        }
    }

    /// Case-insensitive so `#Sam` and `#sam` sit together in the sidebar.
    static func < (lhs: JournalTag, rhs: JournalTag) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

/// Pulls the tags out of a note's text. Nothing is stored: a tag is a fact
/// about the text, and a cached copy is a copy that goes stale.
enum JournalTagScanner {
    /// Every tag in the note, each one expanded with its ancestors so that
    /// filtering on a parent is a plain set membership test.
    static func tags(in text: String) -> Set<JournalTag> {
        let found = inline(in: text).union(frontmatter(in: text))
        return found.reduce(into: Set<JournalTag>()) { all, tag in
            all.insert(tag)
            all.formUnion(tag.ancestors)
        }
    }

    /// `#tag` in the body.
    ///
    /// The `#` has to open the run — start of text, or after whitespace — which
    /// is what keeps `code#4` out. A `#` followed by a space is a Markdown
    /// heading and yields nothing, since the name would be empty.
    static func inline(in text: String) -> Set<JournalTag> {
        var tags: Set<JournalTag> = []
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            defer {
                previous = character
                index = text.index(after: index)
            }
            guard character == "#" else { continue }
            guard previous == nil || previous!.isWhitespace else { continue }

            var end = text.index(after: index)
            while end < text.endIndex, JournalTag.isAllowed(text[end]) {
                end = text.index(after: end)
            }
            if let tag = JournalTag(name: String(text[text.index(after: index)..<end])) {
                tags.insert(tag)
            }
        }
        return tags
    }

    /// A `tags:` key in a YAML front matter block, in either of the two shapes
    /// Obsidian writes: `tags: [a, b]` on the line, or a bullet list under it.
    ///
    /// Deliberately not a YAML parser. A note's front matter is three or four
    /// lines a person typed, and the failure mode of guessing wrong here is one
    /// missing tag, not a corrupted file.
    ///
    /// Stricter than `JournalNote.body(of:)`, which draws the same block for
    /// the renderer: an unterminated `---` yields nothing here, since there is
    /// no block whose keys could be read, where the renderer still has a note
    /// to show. Deliberate, and worth re-reading both before touching either.
    static func frontmatter(in text: String) -> Set<JournalTag> {
        // The block only counts at the very top of the file: a `---` in the
        // middle of a note is a horizontal rule.
        var lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return []
        }
        lines.removeFirst()
        guard let closing = lines.firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line == "---" || line == "..."
        }) else { return [] }

        let block = Array(lines[..<closing])
        guard let keyIndex = block.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("tags:")
        }) else { return [] }

        var names: [String] = []
        let rest = block[keyIndex]
            .trimmingCharacters(in: .whitespaces)
            .dropFirst("tags:".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
        if !rest.isEmpty {
            names = rest.components(separatedBy: ",")
        } else {
            for line in block[block.index(after: keyIndex)...] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- ") else { break }
                names.append(String(trimmed.dropFirst(2)))
            }
        }
        return Set(
            names.compactMap {
                JournalTag(
                    name: $0.trimmingCharacters(
                        in: CharacterSet(charactersIn: " \"'#")
                    )
                )
            }
        )
    }
}

/// The sidebar's tag list: every tag with the number of notes carrying it.
enum JournalTagTally {
    struct Row: Identifiable, Equatable {
        let tag: JournalTag
        let count: Int
        var id: String { tag.name }
    }

    /// Most used first, then alphabetical — the same shape as `SportTally.rows`,
    /// and for the same reason: the tags worth ticking should be reachable
    /// without scrolling.
    static func rows(for noteTags: [Set<JournalTag>]) -> [Row] {
        var counts: [JournalTag: Int] = [:]
        for tags in noteTags {
            for tag in tags { counts[tag, default: 0] += 1 }
        }
        return counts
            .map { Row(tag: $0.key, count: $0.value) }
            .sorted {
                $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count
            }
    }
}
