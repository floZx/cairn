import Foundation
import SwiftData

/// Materialises `JournalAttachment` bytes on disk, so `MarkdownText` and
/// `JournalThumbnails` can resolve `![](pieces-jointes/x.jpg)` against a real
/// URL exactly as they always have — against a folder, not a store.
///
/// The cache is derived and reconstructible, the same way `off.db` is: every
/// file here is written from bytes that already live in the store, under the
/// name the store already holds (`JournalAttachmentRules.fileName`, unique
/// across the whole journal). Deleting this folder loses nothing; `rebuild`
/// puts it back in full from whatever `ModelContext` still has.
enum JournalAttachmentCache {
    /// `<Application Support>/Cairn/cache/journal-attachments/`
    static var directory: URL {
        AppModelContainer.directory.appending(path: "cache/journal-attachments")
    }

    /// Writes `attachment`'s bytes under its file name inside `directory` if
    /// the file is not already there, and returns its URL.
    ///
    /// Writes only when the file is missing: the file name is the key, and
    /// the bytes behind a given name never change, so rewriting an existing
    /// one would only cost time — every launch, for every image the journal
    /// has ever held. Returns nil, and touches no disk at all, when the
    /// attachment carries no bytes: a missing image should stay silent,
    /// never become an empty file that reads as a corrupt one.
    ///
    /// No default value for `directory`: an earlier draft defaulted it to
    /// `Self.directory`, the application's own cache. That is exactly the
    /// shape every test call in this file takes, so a call written without
    /// the second argument — the form the brief's own interface sketch
    /// shows — would silently write into the user's real cache folder
    /// instead of a test's throwaway one. `MirrorEngine.init`'s `cursor:`
    /// carries the identical warning, learned the same way. Every caller,
    /// production and test alike, names the directory it means.
    @discardableResult
    static func materialise(
        _ attachment: JournalAttachment, directory: URL
    ) throws -> URL? {
        guard let data = attachment.data else { return nil }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appending(path: attachment.fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        try data.write(to: url)
        return url
    }

    /// Materialises everything the store holds that is missing on disk.
    ///
    /// Returns the count actually written — zero on every launch after the
    /// first, which is what makes the cache's idempotence testable. No
    /// default for `directory`, for the same reason `materialise` has none:
    /// see its doc comment.
    @discardableResult
    static func rebuild(_ context: ModelContext, directory: URL) throws -> Int {
        let attachments = try context.fetch(FetchDescriptor<JournalAttachment>())
        var written = 0
        for attachment in attachments {
            let url = directory.appending(path: attachment.fileName)
            let existedBefore = FileManager.default.fileExists(atPath: url.path)
            if try materialise(attachment, directory: directory) != nil, !existedBefore {
                written += 1
            }
        }
        return written
    }
}
