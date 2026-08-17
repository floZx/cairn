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
        /// Names — notes and attachments both — that failed to enter the
        /// store as their ordinary bytes: a note whose bytes were not valid
        /// UTF-8, or either one reread and, rarer, unreadable outright.
        /// Imported anyway where that is possible, empty text in the second
        /// case for a note, simply not counted for an attachment.
        var unreadable: [String]
    }

    /// Thrown to abort a run without marking it done: at least one daily
    /// note, or one picture in `pieces-jointes/`, is still an iCloud
    /// placeholder. Never escapes as a documented failure — the point is
    /// only that this run must not succeed at all.
    private struct PendingDownloads: Error {}

    /// Runs once. Returns nil when it did nothing because it had already run.
    ///
    /// Four cases `Tests/JournalImportTests.swift` holds to:
    ///
    /// - No folder was ever designated (`folderPath` nil or empty): the
    ///   marker is set straight away, since there is nothing to recover and
    ///   nothing to retry either.
    /// - The folder cannot be read (unplugged disk, iCloud not yet synced
    ///   down): `JournalFolder.notes(in:)` throws.
    /// - At least one note or picture is still an iCloud placeholder
    ///   (`hasPendingDownloads`): stuck syncing when this ran must not mean
    ///   dropped from the journal for good, so this run aborts the same way
    ///   a folder that cannot be listed does.
    /// - A file exists but fails to decode: it is still counted and still
    ///   imported — see `text(for:)` below — and its name is reported in
    ///   `unreadable`. This run still marks itself done: looping on a
    ///   damaged file at every launch would be worse than taking it in
    ///   imperfectly.
    ///
    /// The first two abort cases share one path: everything throws through
    /// to the `catch` below, which rolls back whatever this run had already
    /// inserted before the error reaches the caller and the marker is left
    /// untouched. Without that, a context whose autosave is on — the one a
    /// future caller may well hand this — would persist a partial run that
    /// the marker says never happened, and the retry it invites would then
    /// duplicate every note that made it in the first time.
    static func runIfNeeded(
        _ context: ModelContext, folderPath: String?, defaults: UserDefaults
    ) throws -> Outcome? {
        guard !defaults.bool(forKey: JournalSettings.importDoneKey) else { return nil }

        guard let folderPath, !folderPath.isEmpty else {
            defaults.set(true, forKey: JournalSettings.importDoneKey)
            return Outcome(notes: 0, attachments: 0, unreadable: [])
        }
        let folder = URL(fileURLWithPath: folderPath)

        do {
            let fileNotes = try JournalFolder.notes(in: folder)

            var unreadable: [String] = []
            for fileNote in fileNotes {
                context.insert(
                    JournalNote(
                        dateKey: fileNote.date,
                        text: text(for: fileNote, in: folder, unreadable: &unreadable)
                    )
                )
            }

            guard !hasPendingDownloads(in: folder) else { throw PendingDownloads() }

            let attachmentCount = importAttachments(
                from: folder, into: context, unreadable: &unreadable
            )

            try context.save()
            defaults.set(true, forKey: JournalSettings.importDoneKey)
            return Outcome(
                notes: fileNotes.count, attachments: attachmentCount, unreadable: unreadable
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// The text a note enters the store with.
    ///
    /// `JournalFolder.notes(in:)` already tried to decode this file as UTF-8
    /// and failed — `isReadable` false is its way of saying so, with an
    /// empty string standing in for what it could not read. Keeping that
    /// empty string would quietly turn a damaged file into a blank note, so
    /// this rereads the file's raw bytes instead and carries them into the
    /// store through `encodeBytesLosslessly`. When even that reread fails —
    /// a permissions problem, say — this falls back to an empty note rather
    /// than aborting the whole run: the file is still named in
    /// `unreadable`, and looping on it at every launch would be worse than
    /// taking it in empty.
    ///
    /// Readable text is not exempt from the one substitution
    /// `encodeBytesLosslessly` makes, either: see `escapingNUL(_:)`.
    private static func text(
        for fileNote: JournalFileNote, in folder: URL, unreadable: inout [String]
    ) -> String {
        guard !fileNote.isReadable else { return escapingNUL(fileNote.text) }
        let url = JournalFolder.url(for: fileNote.date, in: folder)
        unreadable.append(url.lastPathComponent)
        guard let raw = try? Data(contentsOf: url) else { return "" }
        return encodeBytesLosslessly(raw)
    }

    /// Every byte of `data`, carried into a `String` one Unicode scalar per
    /// byte under ISO Latin-1 — total, so this can never fail, and it never
    /// has to throw a byte away or stand a U+FFFD in for one the way a
    /// forced UTF-8 decode would.
    ///
    /// One substitution only: a byte of `0x00` becomes U+E000 (Private Use
    /// Area) rather than U+0000. `Tests/JournalModelTests.swift`'s
    /// `laPersistanceTronqueUneChaineAuPremierNul` proves why —
    /// SwiftData truncates a `String` attribute at an embedded NUL
    /// character on save, silently dropping everything after it, on the
    /// real store as much as the in-memory one used in tests. Every other
    /// byte value round-trips untouched — measured, not merely assumed —
    /// which is exactly why only this one value is touched: the round-trip
    /// bar here is text identical *character* for character, not byte for
    /// byte (`docs/specs/2026-08-17-journal-en-base-design.md`), and
    /// shifting the other 255 as well would fail that bar for nothing.
    /// `JournalNote` gets no column recording which notes passed through
    /// this substitution — a field every row would carry for the sake of
    /// the rare one that needs it.
    private static func encodeBytesLosslessly(_ data: Data) -> String {
        String(
            String.UnicodeScalarView(
                data.map { Unicode.Scalar($0 == 0 ? 0xE000 : UInt32($0))! }
            )
        )
    }

    /// The marker `escapingNUL(_:)` and `unescapingNUL(_:)` use to introduce
    /// an escape pair — never emitted on its own, always followed by a
    /// second scalar that says which of the two source characters this
    /// pair stands for: itself again for a literal `escapeMarker` (the
    /// escape character escapes itself, the same doubling a backslash uses
    /// to escape a literal backslash), or `nulDisambiguator` for a NUL.
    private static let escapeMarker = Unicode.Scalar(0xE000)!
    /// `escapeMarker` followed by this decodes to U+0000.
    private static let nulDisambiguator = Unicode.Scalar(0xE001)!

    /// A two-scalar prefix code, not a single-scalar shift: `0x00` — or,
    /// here, the character U+0000 — becomes `escapeMarker,
    /// nulDisambiguator`, and a literal U+E000 becomes `escapeMarker,
    /// escapeMarker` (doubled). Every other scalar, including a literal
    /// U+E001, passes through untouched.
    ///
    /// A single-scalar shift (U+0000 → U+E000, and — to keep that
    /// injective — U+E000 → U+E001) was tried first and does not work: it
    /// only pushes the collision one code point further out, since nothing
    /// then stops a literal U+E001 landing on the same output as an
    /// escaped U+E000. `escapingNUL("\u{E000}") == escapingNUL("\u{E001}")`
    /// held under that scheme — U+E001 is exactly as typable and as legal
    /// in a UTF-8 file as U+E000, so this is not a hypothetical.
    /// `Tests/JournalMarkdownExportTests.swift`'s round-trip test, run
    /// through the real import and the real export rather than the two
    /// functions directly, is what caught it: a note holding a literal
    /// U+E001 came back as U+E000.
    ///
    /// A prefix code has no such collision because it is self-delimiting:
    /// `unescapingNUL(_:)` never has to guess which of two source
    /// characters a lone escaped scalar stood for, because the escape is
    /// never lone — `escapeMarker` on its own never appears in this
    /// function's output, only as the first half of one of the two pairs
    /// above. Whatever scalar comes right after it is exactly enough to
    /// tell the two apart, and every scalar that is not `escapeMarker`
    /// carries no ambiguity at all, itself included.
    ///
    /// Not `private`: `unescapingNUL(_:)` right below is its exact inverse,
    /// and an export writing `JournalNote.text` back out to a file needs
    /// that inverse to undo this before encoding the result as UTF-8 —
    /// otherwise the substitutions this function makes would reach the file
    /// as the escape pair itself where the original had a NUL or a
    /// private-use character. Kept beside its inverse on purpose: two
    /// functions that answer each other belong at the same address, not
    /// duplicated at their caller's.
    static func escapingNUL(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar {
            case Unicode.Scalar(0)!:
                scalars.append(escapeMarker)
                scalars.append(nulDisambiguator)
            case escapeMarker:
                scalars.append(escapeMarker)
                scalars.append(escapeMarker)
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// The exact inverse of `escapingNUL(_:)`: read left to right, and only
    /// `escapeMarker` ever asks a question — what follows it, which is
    /// always one of the two disambiguators for text this function was
    /// meant to read, decides whether the pair stands for U+0000 or for a
    /// literal U+E000. Every other scalar carries itself through
    /// unconsumed. `Tests/JournalImportTests.swift`'s
    /// `laSubstitutionDuNulEtSonInverseFontLAllerRetour` holds the pair to a
    /// function-to-function round trip rather than a hand-written one, on a
    /// text carrying a NUL, a literal U+E000, and a literal U+E001 all at
    /// once — the case the single-scalar shift this replaced could not
    /// clear.
    ///
    /// A trailing `escapeMarker` with nothing after it, or followed by a
    /// scalar that is neither disambiguator, cannot come from
    /// `escapingNUL(_:)` itself — only from `encodeBytesLosslessly`, which
    /// still emits a lone, unpaired `escapeMarker` for each `0x00` byte on
    /// the reconstructed path. Rather than throw text like that away, that
    /// lone marker is passed through as itself: this function does not
    /// promise a byte-exact inverse of `encodeBytesLosslessly` — see that
    /// function's doc comment on the round-trip bar this clears.
    ///
    /// It does not promise to keep every character on that path either, and
    /// the case is worth naming rather than hiding behind "never loses a
    /// character trying", which is what this comment used to claim: two
    /// consecutive `0x00` bytes reach this function as two consecutive
    /// `escapeMarker`s, which the doubling rule above reads as one literal
    /// U+E000 — two scalars in, one out. That path only ever carries a file
    /// this application already failed to read as UTF-8, whose name is
    /// reported in `Outcome.unreadable` for a human to look at, so the bar
    /// there is "keep something rather than nothing", not fidelity. A note
    /// that came in through `escapingNUL(_:)` — every readable file, which
    /// is to say all of them but the damaged ones — round-trips exactly.
    ///
    /// What an export needs is exactly this, not a byte-level inverse of
    /// `encodeBytesLosslessly`: whatever produced `JournalNote.text` — the
    /// readable path or the reconstructed one — the store now holds a
    /// `String`, and undoing these substitutions before encoding it as
    /// UTF-8 is what writing it back to a file means. For a note that went
    /// through `escapingNUL(_:)` on the way in, that reproduces the
    /// original file's bytes exactly.
    static func unescapingNUL(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == escapeMarker, index + 1 < scalars.count else {
                result.append(scalar)
                index += 1
                continue
            }
            switch scalars[index + 1] {
            case nulDisambiguator:
                result.append(Unicode.Scalar(0)!)
                index += 2
            case escapeMarker:
                result.append(escapeMarker)
                index += 2
            default:
                // Not a pair this function ever produced — a lone marker
                // from `encodeBytesLosslessly`'s reconstructed path. Carried
                // through as itself rather than dropped.
                result.append(scalar)
                index += 1
            }
        }
        return String(result)
    }

    /// Whether the folder still holds at least one iCloud placeholder — a
    /// daily note (`.2026-08-17.md.icloud`) or a picture in
    /// `pieces-jointes/` (`.2026-08-17-1.jpg.icloud`) — the marker
    /// Files.app leaves for something not yet synced down.
    ///
    /// Both, not only notes: the first version of this function only looked
    /// at the folder's root, which closed the hole for notes and left it
    /// wide open for pictures — a `.jpg.icloud` placeholder has the
    /// extension `icloud`, `importAttachments`'s allow-list turns it away
    /// in silence, and the run would have gone on to succeed and mark
    /// itself done with that picture never entering the store.
    ///
    /// `JournalFolder.notes(in:)` already skips note placeholders silently
    /// and starts their download, which is the right behaviour for every
    /// other caller — the folder watcher picks the note up once it lands.
    /// This recovery is the one caller that runs exactly once, so the same
    /// silence would mean something still syncing when it ran never enters
    /// the store at all, not late. Neither `JournalFolder.notes(in:)` nor
    /// `importAttachments` reports what it skipped, so this checks both
    /// directory listings directly.
    private static func hasPendingDownloads(in folder: URL) -> Bool {
        hasPendingDownloads(atPath: folder.path) { JournalFolder.date(fromFileName: $0) != nil }
            || hasPendingDownloads(atPath: JournalFolder.attachmentsFolder(in: folder).path) {
                JournalAttachmentRules.allowedExtensions.contains(
                    URL(fileURLWithPath: $0).pathExtension.lowercased()
                )
            }
    }

    /// One directory's placeholders, matched against whatever makes a name
    /// a real one for that directory — a date for notes, an allowed
    /// extension for attachments. A directory that cannot be listed (no
    /// `pieces-jointes/` at all, the ordinary case) holds none.
    private static func hasPendingDownloads(
        atPath path: String, validName isValid: (String) -> Bool
    ) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path)
        else { return false }
        return names.contains { name in
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return false }
            return isValid(String(name.dropFirst().dropLast(".icloud".count)))
        }
    }

    /// Every picture in `pieces-jointes/`, orphaned or not.
    ///
    /// All of them, not only the ones a note's Markdown happens to link to:
    /// an orphaned image costs nothing kept, while a missing one breaks
    /// whichever note pointed at it. A folder with no attachments at all —
    /// most journals — is not an error, so a missing sub-directory yields
    /// zero rather than throwing.
    ///
    /// Filtered by `JournalAttachmentRules.allowedExtensions`, the same
    /// list a paste or a drop is held to: without it, `contentsOfDirectory`
    /// hands back everything in the folder without distinction —
    /// `.DS_Store`, a stray sub-directory — and each would otherwise become
    /// a `JournalAttachment` of its own, or abort the run trying to read
    /// one as `Data`. An `.icloud` placeholder is turned away by the same
    /// check, but `hasPendingDownloads` is what stands between it and being
    /// silently dropped for good — this function runs only once that has
    /// confirmed there is none left to worry about.
    ///
    /// A name that passes the extension check but still fails to read — a
    /// permissions problem, a name that turned out to be a directory — is
    /// not silently dropped either: it goes into `unreadable`, the same
    /// list a damaged note's name goes into, rather than disappearing
    /// without a trace the way an early version of this function let it.
    private static func importAttachments(
        from folder: URL, into context: ModelContext, unreadable: inout [String]
    ) -> Int {
        let attachmentsFolder = JournalFolder.attachmentsFolder(in: folder)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: attachmentsFolder.path
        ) else { return 0 }

        var count = 0
        for name in names.sorted() {
            let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
            guard JournalAttachmentRules.allowedExtensions.contains(ext) else { continue }
            guard let data = try? Data(contentsOf: attachmentsFolder.appending(path: name))
            else {
                unreadable.append(name)
                continue
            }
            context.insert(JournalAttachment(fileName: name, data: data))
            count += 1
        }
        return count
    }
}
