import Foundation

/// What a photo dropped on a note becomes: a file name, and a line of Markdown.
///
/// A value-only piece, like everything in this feature that is not
/// `JournalFolder`: naming a file and appending a line are decisions worth
/// testing, and neither needs a disk to be made.
enum JournalAttachmentRules {
    /// Beside the notes, not among them: a vault whose root fills with images
    /// is a vault where the notes get hard to find.
    static let folderName = "pieces-jointes"

    /// What a journal takes. Anything else dropped on a note is refused out
    /// loud — a file ignored in silence is a file one believes was added.
    static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]

    /// The longest side a picture keeps in the vault.
    ///
    /// A phone takes 3024 × 4032 and a journal never shows more than the width
    /// of a pane, or of a printed page. Storing the original meant a megabyte
    /// per line in a vault that syncs over iCloud, and a full decode every time
    /// a row was drawn — measured at a second, on the main thread, for one
    /// photo. Anything already smaller is copied untouched: re-encoding a file
    /// that costs nothing would only lose detail.
    static let maxPixels = 2048

    /// `AAAA-MM-JJ-N.ext`, N being the first free number of that day.
    ///
    /// The original name is dropped on purpose: it comes from a camera or a
    /// screenshot, it says nothing, and two "IMG_4032.jpg" would eventually
    /// meet. The number is taken regardless of extension — two files differing
    /// only by theirs would read as the same photo.
    static func fileName(
        for date: DateKey, extension ext: String, taken: Set<String>
    ) -> String {
        let stems = Set(
            taken.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
            }
        )
        var number = 1
        while stems.contains("\(date.raw)-\(number)") { number += 1 }
        return "\(date.raw)-\(number).\(ext.lowercased())"
    }

    /// Plain Markdown, not Obsidian's `![[…]]`: Obsidian reads both, and the
    /// book's HTML has no reason to learn a syntax one application owns.
    static func link(to fileName: String) -> String {
        "![](\(folderName)/\(fileName))"
    }

    /// The links at the end of the note, each on its own line.
    ///
    /// A blank line before them when there is text to part from, and none when
    /// the note is empty or already ends in one: a note that opens on a blank
    /// line looks like a note someone started by accident.
    static func appending(_ links: [String], to text: String) -> String {
        guard !links.isEmpty else { return text }
        let body = links.joined(separator: "\n")
        guard !text.isEmpty else { return body }
        if text.hasSuffix("\n\n") { return text + body }
        if text.hasSuffix("\n") { return text + "\n" + body }
        return text + "\n\n" + body
    }
}
