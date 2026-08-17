import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The only place that touches the disk.
///
/// Everything else in the Journal works on values, which is what makes it
/// testable without a file system — and what makes the rules about what is and
/// is not a note readable in one place.
enum JournalFolder {
    static let fileExtension = "md"

    static func fileName(for date: DateKey) -> String {
        "\(date.raw).\(fileExtension)"
    }

    /// The daily note this file name stands for, or nil.
    ///
    /// `DateKey(raw:)` is the whole validation: it already refuses anything
    /// that is not exactly `AAAA-MM-JJ`, month and day included, which is why
    /// no `DateFormatter` appears anywhere in this feature.
    static func date(fromFileName name: String) -> DateKey? {
        let url = URL(fileURLWithPath: name)
        guard url.pathExtension == fileExtension else { return nil }
        return DateKey(raw: url.deletingPathExtension().lastPathComponent)
    }

    static func url(for date: DateKey, in folder: URL) -> URL {
        folder.appending(path: fileName(for: date))
    }

    /// Every daily note at the root of `folder`, newest first.
    ///
    /// `contentsOfDirectory` is shallow by nature — unlike `enumerator(at:)`,
    /// it never walks into sub-directories, so none is needed here. Files
    /// that are not daily notes do not exist as far as Cairn is concerned —
    /// choosing a whole Obsidian vault must not drag its entire contents into
    /// a journal.
    static func notes(in folder: URL) throws -> [JournalFileNote] {
        let names = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        )
        var notes: [JournalFileNote] = []
        for url in names {
            if let pending = pendingDownload(at: url) {
                // A vault synced by iCloud shows not-yet-downloaded notes as
                // `.2026-08-11.md.icloud` placeholders. Asking for the file is
                // all that is needed: the folder watcher picks it up when it
                // lands, so this pass simply skips it.
                try? FileManager.default.startDownloadingUbiquitousItem(at: pending)
                continue
            }
            guard let date = date(fromFileName: url.lastPathComponent) else { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                notes.append(JournalFileNote(date: date, text: text))
            } else {
                notes.append(JournalFileNote(date: date, text: "", isReadable: false))
            }
        }
        return notes.sorted { $0.date > $1.date }
    }

    // MARK: - Pièces jointes

    static func attachmentsFolder(in folder: URL) -> URL {
        folder.appending(path: JournalAttachment.folderName)
    }

    /// Copies a picture into the vault under a name of the journal's own.
    ///
    /// Copied and not moved: the photo the user dropped goes on living where
    /// it was, in a library or a download folder, and a journal that swallowed
    /// originals would be a journal one stops dropping things on.
    ///
    /// - Returns: the name written, which is what the note's link points at.
    @discardableResult
    static func copyAttachment(
        from source: URL, for date: DateKey, in folder: URL
    ) throws -> String {
        // Reduced on the way in, when it is worth it: see
        // `JournalAttachment.maxPixels`. A picture already small enough is
        // copied byte for byte — re-encoding it would only lose detail.
        if let reduced = reduced(at: source) {
            return try writeAttachment(
                reduced, extension: "jpg", for: date, in: folder
            )
        }
        let name = try prepareName(
            extension: source.pathExtension, for: date, in: folder
        )
        try FileManager.default.copyItem(
            at: source, to: attachmentsFolder(in: folder).appending(path: name)
        )
        return name
    }

    /// The same from bytes, for what a paste hands over.
    static func reduced(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return reduced(source)
    }

    /// The picture at `url`, brought down to `JournalAttachment.maxPixels`, or
    /// nil when it is already within it.
    ///
    /// Through ImageIO, which makes the smaller image without ever decoding
    /// the whole one, and which carries the EXIF orientation over — a photo
    /// taken sideways would otherwise land on its side for good.
    static func reduced(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return reduced(source)
    }

    private static func reduced(_ source: CGImageSource) -> Data? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > JournalAttachment.maxPixels,
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source, 0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: JournalAttachment.maxPixels,
                  ] as CFDictionary
              )
        else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The same from bytes — what a paste hands over: the clipboard carries an
    /// image far more often than it carries a file.
    @discardableResult
    static func writeAttachment(
        _ data: Data, extension ext: String, for date: DateKey, in folder: URL
    ) throws -> String {
        let name = try prepareName(extension: ext, for: date, in: folder)
        try data.write(to: attachmentsFolder(in: folder).appending(path: name))
        return name
    }

    /// A free name, with the folder made ready to receive it.
    private static func prepareName(
        extension ext: String, for date: DateKey, in folder: URL
    ) throws -> String {
        let attachments = attachmentsFolder(in: folder)
        try FileManager.default.createDirectory(
            at: attachments, withIntermediateDirectories: true
        )
        let taken = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: attachments.path))
                ?? []
        )
        return JournalAttachment.fileName(for: date, extension: ext, taken: taken)
    }

    /// The real file behind an iCloud placeholder, or nil when this is not one.
    private static func pendingDownload(at url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let real = String(name.dropFirst().dropLast(".icloud".count))
        guard date(fromFileName: real) != nil else { return nil }
        return url.deletingLastPathComponent().appending(path: real)
    }

    static func write(_ text: String, for date: DateKey, in folder: URL) throws {
        try Data(text.utf8).write(to: url(for: date, in: folder), options: .atomic)
    }

    /// - Parameter toTrash: true for a deletion the user asked for — these are
    ///   their files in their own vault, and a mistake has to be undoable.
    ///   False for a note emptied to nothing, which never held anything worth
    ///   filling a trash with.
    static func remove(_ date: DateKey, in folder: URL, toTrash: Bool) throws {
        let target = url(for: date, in: folder)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        if toTrash {
            try FileManager.default.trashItem(at: target, resultingItemURL: nil)
        } else {
            try FileManager.default.removeItem(at: target)
        }
    }
}
