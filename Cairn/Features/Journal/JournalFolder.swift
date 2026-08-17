import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The one place that knows how to read a folder of daily notes.
///
/// Reading only, since the notes moved into the base: this half stays for the
/// recovery, which is now its only caller — a fresh installation, or a store
/// restored from an old backup, still has a first launch to make. Everything
/// that wrote into the folder has gone with the folder itself: Cairn reads it
/// once and never touches it again, which is what makes an automatic recovery
/// safe to run without asking.
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

    /// Where that day's note sits. Kept although nothing writes any more:
    /// `JournalImport` rereads the raw bytes of a file that would not decode
    /// as UTF-8, and this is how it names it.
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
                // `.2026-08-11.md.icloud` placeholders. The download is asked
                // for and the file skipped — there is no watcher any more to
                // pick it up when it lands, which is exactly why the recovery
                // does not rely on this: `JournalImport.hasPendingDownloads`
                // counts the placeholders itself and refuses to run at all
                // while there is one, rather than letting a note still syncing
                // be dropped for good by a pass that happens only once.
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
        folder.appending(path: JournalAttachmentRules.folderName)
    }

    // MARK: - Réduction des images

    /// A picture brought down to `JournalAttachmentRules.maxPixels`, or nil
    /// when it is already within it.
    ///
    /// Kept here rather than following the writing out of this file: reducing
    /// an image is what `JournalStore` does to every picture entering the
    /// base, and the rule — through ImageIO, orientation carried over, an
    /// already-small picture left alone — has nothing to do with folders.
    ///
    /// This form for what a paste hands over: the clipboard carries an image
    /// far more often than it carries a file.
    static func reduced(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return reduced(source)
    }

    /// The same from a file, which is what a drop hands over.
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
              max(width, height) > JournalAttachmentRules.maxPixels,
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source, 0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: JournalAttachmentRules.maxPixels,
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

    /// The real file behind an iCloud placeholder, or nil when this is not one.
    private static func pendingDownload(at url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let real = String(name.dropFirst().dropLast(".icloud".count))
        guard date(fromFileName: real) != nil else { return nil }
        return url.deletingLastPathComponent().appending(path: real)
    }
}
