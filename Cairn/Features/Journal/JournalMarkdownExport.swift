import Foundation
import SwiftData

/// Writes the store's journal back out as the Markdown folder
/// `JournalImport` once read in — the other half of the round trip
/// `Tests/JournalMarkdownExportTests.swift` holds to. Not called from
/// anywhere yet: task 8 is what wires this into the backup service.
///
/// The bar, from `docs/specs/2026-08-17-journal-en-base-design.md`: a note's
/// text comes back identical *character* for character, and an attachment's
/// bytes identical *byte* for byte. No reformatting, no re-encoding, no
/// rewritten link — which is exactly why this writes `note.text`, put
/// through `JournalImport.unescapingNUL(_:)`, as raw UTF-8 and nothing more:
/// no added trailing newline, no line-ending normalisation, no touching
/// `![](pieces-jointes/…)` links already sitting in the text.
enum JournalMarkdownExport {
    /// Writes one `AAAA-MM-JJ.md` per note plus `pieces-jointes/` into
    /// `destination`, which it creates. Returns how many notes it wrote.
    @discardableResult
    static func write(_ context: ModelContext, to destination: URL) throws -> Int {
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true
        )

        let notes = try context.fetch(FetchDescriptor<JournalNote>())
        var written = 0
        for note in notes {
            // Every `JournalNote` in the store was built from a validated
            // `DateKey` — by `JournalImport` today, by nothing else yet —
            // so `dateKey` failing to parse `dateKeyRaw` back is not a case
            // this has to invent behaviour for. Skipped rather than
            // crashing: an export is not the place to first discover a row
            // some future writer left malformed.
            guard let dateKey = note.dateKey else { continue }
            // `note.text` carries `escapingNUL`'s substitutions —
            // U+0000 → U+E000, and a literal U+E000 → U+E001, so the pair
            // stays injective. `unescapingNUL` undoes exactly that before
            // this ever becomes UTF-8 bytes: skipping it would send U+E000
            // to the file in place of the NUL the user actually wrote, a
            // real change of character rather than of encoding.
            let text = JournalImport.unescapingNUL(note.text)
            try Data(text.utf8).write(
                to: destination.appending(path: JournalFolder.fileName(for: dateKey)),
                options: .atomic
            )
            written += 1
        }

        let attachments = try context.fetch(FetchDescriptor<JournalAttachment>())
        if !attachments.isEmpty {
            let attachmentsFolder = destination.appending(
                path: JournalAttachmentRules.folderName
            )
            try FileManager.default.createDirectory(
                at: attachmentsFolder, withIntermediateDirectories: true
            )
            for attachment in attachments {
                // `data` is optional only because `@Attribute(.externalStorage)`
                // makes every stored property one; `JournalAttachment.init`
                // never leaves it nil. Skipped, not crashed on, for the same
                // reason as a malformed `dateKeyRaw` above.
                guard let data = attachment.data else { continue }
                try data.write(
                    to: attachmentsFolder.appending(path: attachment.fileName), options: .atomic
                )
            }
        }

        return written
    }
}
