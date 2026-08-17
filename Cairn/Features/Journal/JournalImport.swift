import Foundation
import SwiftData

/// The journal folder's one-time recovery into the store.
///
/// Reads every daily note and every picture under `pieces-jointes/` once,
/// writes them into SwiftData, and never touches the folder again — the
/// coupure nette described in `docs/specs/2026-08-17-journal-en-base-design.md`.
/// Nothing here moves, renames, or deletes anything on disk, and nothing
/// writes a marker into the folder itself: the marker lives in `UserDefaults`,
/// which is what makes an automatic recovery safe to run without asking.
enum JournalImport {
    /// What one run did. `nil` from `runIfNeeded` means it did nothing at
    /// all — not "nothing new" — because the marker, not a diff against what
    /// is already in the store, is what stops a second run.
    struct Outcome: Equatable {
        var notes: Int
        var attachments: Int
        /// File names that could not be decoded, imported byte-for-byte anyway.
        var unreadable: [String]
    }

    /// Runs once. Returns nil when it did nothing because it had already run.
    ///
    /// Three cases the three tests below hold to:
    ///
    /// - No folder was ever designated (`folderPath` nil or empty): the
    ///   marker is set straight away, since there is nothing to recover and
    ///   nothing to retry either.
    /// - The folder cannot be read (unplugged disk, iCloud not yet synced
    ///   down): `JournalFolder.notes(in:)` throws, this function propagates
    ///   that error *before* touching the marker, and the next launch tries
    ///   again. Marking a run that read nothing as done would lose the whole
    ///   journal for good.
    /// - A file exists but fails to decode: it is still counted and still
    ///   imported — see `text(for:)` below — and its name is reported in
    ///   `unreadable`. The run still marks itself done: looping on a damaged
    ///   file at every launch would be worse than taking it in imperfectly.
    static func runIfNeeded(
        _ context: ModelContext, folderPath: String?, defaults: UserDefaults
    ) throws -> Outcome? {
        guard !defaults.bool(forKey: JournalSettings.importDoneKey) else { return nil }

        guard let folderPath, !folderPath.isEmpty else {
            defaults.set(true, forKey: JournalSettings.importDoneKey)
            return Outcome(notes: 0, attachments: 0, unreadable: [])
        }
        let folder = URL(fileURLWithPath: folderPath)

        // Left to throw straight out: a folder that cannot be listed must not
        // reach the line that sets the marker below.
        let fileNotes = try JournalFolder.notes(in: folder)

        var unreadable: [String] = []
        for fileNote in fileNotes {
            context.insert(
                JournalNote(
                    dateKey: fileNote.date,
                    text: try text(for: fileNote, in: folder, unreadable: &unreadable)
                )
            )
        }

        let attachmentCount = try importAttachments(from: folder, into: context)

        try context.save()
        defaults.set(true, forKey: JournalSettings.importDoneKey)
        return Outcome(
            notes: fileNotes.count, attachments: attachmentCount, unreadable: unreadable
        )
    }

    /// The text a note enters the store with.
    ///
    /// `JournalFolder.notes(in:)` already read this file once and gave up an
    /// empty string on it — `isReadable` false is its way of saying the bytes
    /// were not valid UTF-8. Rather than keep that empty string, which would
    /// quietly turn a damaged file into a blank note, this rereads the file's
    /// raw bytes and carries them into the store through ISO Latin-1: a total,
    /// one-to-one mapping from every byte value to one Unicode scalar, so
    /// nothing is lost, guessed at, or replaced with U+FFFD the way decoding
    /// as UTF-8 would. `name` is appended to `unreadable` here, next to the
    /// only place that knows this file failed to decode as text.
    private static func text(
        for fileNote: JournalFileNote, in folder: URL, unreadable: inout [String]
    ) throws -> String {
        guard !fileNote.isReadable else { return fileNote.text }
        let url = JournalFolder.url(for: fileNote.date, in: folder)
        let raw = try Data(contentsOf: url)
        unreadable.append(url.lastPathComponent)
        return String(data: raw, encoding: .isoLatin1) ?? ""
    }

    /// Every picture in `pieces-jointes/`, orphaned or not.
    ///
    /// All of them, not only the ones a note's Markdown happens to link to:
    /// an orphaned image costs nothing kept, while a missing one breaks
    /// whichever note pointed at it. A folder with no attachments at all —
    /// most journals — is not an error, so a missing sub-directory yields
    /// zero rather than throwing.
    private static func importAttachments(
        from folder: URL, into context: ModelContext
    ) throws -> Int {
        let attachmentsFolder = JournalFolder.attachmentsFolder(in: folder)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: attachmentsFolder.path
        ) else { return 0 }

        for name in names.sorted() {
            let data = try Data(contentsOf: attachmentsFolder.appending(path: name))
            context.insert(JournalAttachment(fileName: name, data: data))
        }
        return names.count
    }
}
