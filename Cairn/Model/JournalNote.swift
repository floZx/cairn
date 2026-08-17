import Foundation
import SwiftData

/// One day's note, as the database holds it.
///
/// As opposed to `JournalFileNote`, what one file on disk said at one
/// moment: this is what the store keeps. `tags` was derived at construction
/// there, which a `@Model` cannot do — nothing recomputes a stored property
/// on fetch — so it becomes the `tagsRaw` column, and `setText` is the one
/// place that keeps it current with `text`.
@Model
final class JournalNote {
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

    var dateKeyRaw: String = ""
    /// Readable freely, but settable only through `setText` from outside
    /// this file: a direct assignment would leave `tagsRaw` describing a
    /// text that is no longer there, which is exactly the silent drift
    /// `setText` exists to prevent.
    private(set) var text: String = ""
    /// `JournalTag.name` values, without their `#` — kept in step with
    /// `text` by `setText`, never written anywhere else.
    private(set) var tagsRaw: [String] = []
    private(set) var updatedAt: Date = Date.distantPast

    init(dateKey: DateKey, text: String) {
        self.dateKeyRaw = dateKey.raw
        setText(text)
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }

    var tags: Set<JournalTag> {
        Set(tagsRaw.compactMap { JournalTag(name: $0) })
    }

    /// Whitespace only — the same rule `JournalFileNote.isEmpty` uses, kept
    /// in step with it on purpose: a note that was empty on disk must read
    /// as empty once it is a row.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The only path that writes `text`. It poses `tagsRaw` and `updatedAt`
    /// together: a text saved without recomputing its tags would be a note
    /// that silently drops out of the sidebar's tag filters.
    func setText(_ text: String) {
        self.text = text
        self.tagsRaw = JournalTagScanner.tags(in: text).map(\.name)
        self.updatedAt = Date()
    }

    /// What `MirrorEngine.pull()` applies: a text written on another device,
    /// with the moment its author wrote it.
    ///
    /// `setText` would be wrong here on its one remaining line — it stamps
    /// `updatedAt = Date()`, the moment of *arrival*, which would make every
    /// pulled note look freshly edited on this Mac. The next push would then
    /// send it straight back as if the Mac had authored it, and the note
    /// would win any later arbitration against its own source. `editedAt` is
    /// the web's clock, and copying it is what keeps the two sides ordered.
    ///
    /// The tags are recomputed here rather than taken from the row, even
    /// though the row carries `tags_raw`: `JournalTagScanner` is this app's
    /// rule, the web holds a port of it, and where the two ever disagree the
    /// original is the one that should decide what this store keeps.
    func applyMirrored(text: String, editedAt: Date) {
        setText(text)
        self.updatedAt = editedAt
    }
}
