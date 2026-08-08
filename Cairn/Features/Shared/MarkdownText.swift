import SwiftUI

/// A note, rendered.
///
/// Blocks come from `MarkdownParser`; the inline formatting inside each one is
/// left to `Text`, which already understands bold, italic, code and links.
struct MarkdownText: View {
    let markdown: String

    private var blocks: [MarkdownBlock] { MarkdownParser.blocks(from: markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case let .heading(level, text):
                    Self.inline(text)
                        .font(headingFont(level))
                        // Air above a heading and not below it: the gap belongs
                        // to what the heading separates from, not to what it
                        // introduces.
                        .padding(.top, block == blocks.first ? 0 : 6)
                case let .paragraph(text):
                    Self.inline(text)
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
                        Self.inline(text)
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
            Text(symbol)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                // A gutter, so the text of every item starts at the same place
                // whether the marker is "•" or "10.".
                .frame(width: 22, alignment: .trailing)
            Self.inline(text)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.bold()
        case 2: .headline
        default: .subheadline.bold()
        }
    }

    /// Inline Markdown, or the raw text when it will not parse.
    ///
    /// Falling back rather than throwing: a stray bracket in a note must show
    /// the note, not an error — and `AttributedString` refuses more input than
    /// one would expect.
    static func inline(_ text: String) -> Text {
        guard let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return Text(text)
        }
        return Text(attributed)
    }
}
