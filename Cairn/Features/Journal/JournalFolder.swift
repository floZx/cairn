import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The journal's file conventions, from when it lived in a folder of daily
/// notes: the name a day's note takes, and the size a picture is brought
/// down to. The Markdown export still writes that folder's format.
enum JournalFolder {
    static let fileExtension = "md"

    static func fileName(for date: DateKey) -> String {
        "\(date.raw).\(fileExtension)"
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
}
