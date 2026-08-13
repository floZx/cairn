import AppKit
import ImageIO
import SwiftUI

/// The pictures a note shows in the list, and where they come from.
///
/// A row is drawn again on every hover, every selection, every keystroke in
/// the search field. Decoding a JPEG from the vault each of those times is how
/// a list starts to stutter, so the decoded thumbnails are kept — small, few,
/// and dropped oldest-first once there are more than a screenful.
@MainActor
enum JournalThumbnails {
    /// Two, and a count for the rest.
    ///
    /// The strip shares the title's line rather than taking one of its own, so
    /// what it may occupy is whatever the name and the excerpt leave. Two
    /// squares say "there are pictures here" without pushing the words about.
    static let limit = 2

    /// The side of one thumbnail, in points. Square on purpose: a strip of
    /// mixed aspect ratios reads as a broken layout rather than as a set.
    static let side: CGFloat = 34

    /// What a row shows: the first few paths, and how many were left out.
    static func strip(of paths: [String]) -> (shown: [String], extra: Int) {
        (Array(paths.prefix(limit)), max(0, paths.count - limit))
    }

    /// The picture at that path in the vault, decoded once.
    ///
    /// Nil for anything that will not read: a file still coming down from
    /// iCloud, or a link to something that was moved. The row then shows one
    /// thumbnail fewer rather than an empty frame, because a list is scanned
    /// and a hole in it reads as a fault.
    static func image(at path: String, in folder: URL?) -> NSImage? {
        guard let folder else { return nil }
        let url = folder.appending(path: path)
        let key = url.path
        if let cached = cache[key] { return cached }

        let image = thumbnail(at: url)
        cache[key] = image
        order.append(key)
        evictIfNeeded()
        return image
    }

    /// Forgotten wholesale when the vault changes: another folder is another
    /// set of pictures, and a path is only unique within one.
    static func removeAll() {
        cache.removeAll()
        order.removeAll()
    }

    private static let capacity = 60
    private static var cache: [String: NSImage?] = [:]
    private static var order: [String] = []

    /// A thumbnail read straight from the file, at the size it will be drawn.
    ///
    /// Through ImageIO rather than `NSImage(contentsOf:)` followed by a draw,
    /// which decodes the whole picture before shrinking it. Measured on this
    /// vault, 13 August 2026: a 3024 × 4032 photo from a phone cost **1013 ms**
    /// that way and 24 ms this way. That second was spent on the main thread,
    /// which is why walking the list with `j` stalled on any day carrying one.
    ///
    /// `WithTransform` because a photo taken sideways carries its orientation
    /// in EXIF and nothing else here would apply it — `NSImage` did that part
    /// for us.
    private static func thumbnail(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source, 0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      // Twice the drawn side, for a retina screen.
                      kCGImageSourceThumbnailMaxPixelSize: side * 2,
                  ] as CFDictionary
              )
        else { return nil }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private static func evictIfNeeded() {
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
    }
}

/// The strip itself: a few squares, then how many more there are.
struct JournalThumbnailStrip: View {
    let paths: [String]
    let folder: URL?

    var body: some View {
        let strip = JournalThumbnails.strip(of: paths)
        let images = strip.shown.compactMap {
            JournalThumbnails.image(at: $0, in: folder)
        }
        if !images.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: JournalThumbnails.side,
                            height: JournalThumbnails.side
                        )
                        .clipShape(.rect(cornerRadius: 4))
                }
                if strip.extra > 0 {
                    Text("+\(strip.extra)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: JournalThumbnails.side, minHeight: JournalThumbnails.side)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 4))
                }
            }
        }
    }
}
