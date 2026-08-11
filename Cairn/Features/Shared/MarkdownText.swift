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

    private var blocks: [MarkdownBlock] { MarkdownParser.blocks(from: markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case let .heading(level, text):
                    inline(text)
                        .font(headingFont(level))
                        // Air above a heading and not below it: the gap belongs
                        // to what the heading separates from, not to what it
                        // introduces.
                        .padding(.top, block == blocks.first ? 0 : 6)
                case let .paragraph(text):
                    sized(inline(text))
                case let .bullet(text):
                    marker("•", text)
                case let .numbered(number, text):
                    marker("\(number).", text)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return Text(hidingTagHashes ? withoutTagHashes(attributed) : attributed)
    }

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
