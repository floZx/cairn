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
    /// Three cases `Tests/JournalImportTests.swift` holds to:
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
    /// `JournalFolder.notes(in:)` already tried to decode this file as UTF-8
    /// and failed — `isReadable` false is its way of saying so, with an empty
    /// string standing in for what it could not read. Keeping that empty
    /// string would quietly turn a damaged file into a blank note, so this
    /// rereads the file's raw bytes instead and carries them into the store
    /// through `encodeBytesLosslessly`, below.
    ///
    /// What this does *not* promise: that exporting the note later
    /// reproduces the original bytes. A note built this way, re-encoded as
    /// UTF-8 on the way out — which is what a plain `Data(text.utf8)` export
    /// does, the same one `JournalFolder.write` uses today — comes back as
    /// different bytes, even though no character was lost or altered on the
    /// way in: `encodeBytesLosslessly` is bijective, `Data(text.utf8)` is
    /// not the matching inverse of it.
    /// `docs/specs/2026-08-17-journal-en-base-design.md` sets the
    /// round-trip bar at *character*-identical text and *byte*-identical
    /// images, not byte-identical text, and this satisfies exactly that bar.
    ///
    /// That gap is acceptable because the file this reconstructs from is
    /// never touched: recovery only ever reads it, so the original stays on
    /// the user's disk, unedited, for as long as they keep it. A note that
    /// comes back as something else on export is a copy going astray, not
    /// the only record of it disappearing — the source of truth was never
    /// at risk. Deliberately not solved by adding a flag to `JournalNote` to
    /// tell such a note apart from an ordinary one: that would be a column
    /// every row carries for the sake of the rare one that needs it, and
    /// tranche 3 would have to carry it all the way to Supabase too. The
    /// file on disk is the backup of last resort; that is enough.
    private static func text(
        for fileNote: JournalFileNote, in folder: URL, unreadable: inout [String]
    ) throws -> String {
        guard !fileNote.isReadable else { return fileNote.text }
        let url = JournalFolder.url(for: fileNote.date, in: folder)
        let raw = try Data(contentsOf: url)
        unreadable.append(url.lastPathComponent)
        return encodeBytesLosslessly(raw)
    }

    /// Every byte of `data`, carried into a `String` one Unicode scalar per
    /// byte — total and bijective, so nothing is lost, guessed at, or
    /// replaced with U+FFFD the way a forced UTF-8 decode would be.
    ///
    /// Shifted into the Private Use Area (U+E000...U+E0FF) rather than left
    /// at each byte's own value, which would be plain ISO Latin-1
    /// (U+0000...U+00FF) — the first version of this function used exactly
    /// that, and it lost data anyway. A byte of 0x00 becomes the scalar
    /// U+0000, and SwiftData's persistence truncates a `String` attribute at
    /// an embedded NUL character on save — the classic C-string-length bug —
    /// silently dropping everything after it. Measured directly against
    /// this store, not read about: every other byte value round-tripped
    /// correctly under Latin-1, only 0x00 did not, in exactly the way this
    /// function exists to prevent. Shifting the whole range into the
    /// Private Use Area sidesteps the bug for every byte at once, rather
    /// than special-casing 0x00 and leaving a mapping that still assumes
    /// the store will accept whichever scalar a byte happens to produce.
    private static func encodeBytesLosslessly(_ data: Data) -> String {
        String(
            String.UnicodeScalarView(
                data.map { Unicode.Scalar(0xE000 + UInt32($0))! }
            )
        )
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
