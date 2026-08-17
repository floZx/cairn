import Foundation
import SwiftData

/// One image dropped on a note, kept as bytes rather than as a link.
///
/// As opposed to `JournalAttachmentRules`, which only names a file and
/// composes the Markdown that points at it: this is where the bytes
/// themselves live, in external storage, beside `ActivityPhoto.data`.
@Model
final class JournalAttachment {
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

    /// `JournalAttachmentRules.fileName(for:extension:taken:)`'s output — the
    /// key a note's Markdown link points at.
    var fileName: String = ""

    @Attribute(.externalStorage) var data: Data?

    var addedAt: Date = Date.distantPast

    /// When these bytes reached Supabase Storage, nil until they have.
    ///
    /// Local bookkeeping only, never a mirrored column:
    /// `Tests/MirrorRowSchemaTests.swift` fails if `mirrorRow(userID:)` ever
    /// starts emitting it. Optional with no default beyond `nil`, so an
    /// existing store migrates without a value to backfill.
    var mirroredAt: Date?

    init(fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
        self.addedAt = Date()
    }
}
