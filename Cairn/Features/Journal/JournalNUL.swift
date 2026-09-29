import Foundation

/// The escape the journal's notes went through when they were taken in from
/// the old Markdown folder, and the one the export undoes.
///
/// SwiftData truncates a `String` attribute at an embedded NUL on save,
/// silently dropping everything after it (`Tests/JournalModelTests.swift`,
/// `laPersistanceTronqueUneChaineAuPremierNul`). The recovery from the
/// folder therefore stored every U+0000 as an escape pair, and the notes
/// taken in then still carry them: `JournalMarkdownExport` has to undo them
/// before a note becomes UTF-8 again. The recovery itself is gone; the
/// escape outlives it in the store.
enum JournalNUL {
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
    /// A round trip through the import and the export, rather than the two
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
    /// unconsumed. `Tests/JournalNULTests.swift` holds the pair to a
    /// function-to-function round trip, on a text carrying a NUL, a literal
    /// U+E000 and a literal U+E001 all at once.
    ///
    /// A lone `escapeMarker` — trailing, or followed by neither
    /// disambiguator — cannot come from `escapingNUL(_:)`. The old folder's
    /// recovery could leave one in a note it had to rebuild from bytes that
    /// were not UTF-8; it is passed through as itself rather than dropped.
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
                // from the recovery's reconstructed path. Carried
                // through as itself rather than dropped.
                result.append(scalar)
                index += 1
            }
        }
        return String(result)
    }
}
