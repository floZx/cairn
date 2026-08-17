import Foundation

/// The journal's two models, as mirror rows.
///
/// Added in tranche 3, after the journal moved into the store: the web app
/// needs the notes, and the notes now live somewhere a mirror can reach.

extension JournalNote: MirrorRow {
    static var mirrorTable: String { "journal_note" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "date_key_raw": .string(dateKeyRaw),
            "text": .string(text),
            "tags_raw": .stringArray(tagsRaw),
            // Not `updated_at`: that column is the server's own, posted by the
            // trigger and read only by the pull cursor. `Athlete.updatedAt`
            // met the same collision first and answered it the same way.
            "note_updated_at": .date(updatedAt),
        ]
    }
}

extension JournalAttachment: MirrorRow {
    static var mirrorTable: String { "journal_attachment" }

    /// Where this picture's bytes live in the `photos` bucket — the same
    /// string `mirrorRow(userID:)` writes to `storage_path` and
    /// `MirrorEngine.uploadPendingBlobs()` uploads to, kept in one place so
    /// the two can never drift apart.
    ///
    /// Under a `journal/` prefix rather than beside the activity photos: the
    /// file name is unique across the journal, not across the whole library,
    /// and a picture named `2026-08-12-1.jpg` has no reason to be able to
    /// collide with a Strava photo id.
    func blobStoragePath(userID: String) -> String { "\(userID)/journal/\(fileName)" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "file_name": .string(fileName),
            "added_at": .date(addedAt),
            // The bytes go to Storage, never into the row: 4 pictures today,
            // but a journal accumulates them, and a 500 MB database is not
            // where megabytes belong.
            "storage_path": .string(blobStoragePath(userID: userID)),
        ]
    }
}
