import AppKit
import ImageIO
import SwiftData
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

    /// Where one thumbnail comes from.
    ///
    /// Two origins, one strip: a picture written into the note is named by a
    /// path and read from the attachment cache, one carried by an outing is
    /// bytes fetched straight from the store. What the row says — "there are
    /// pictures here" — is the same either way, and a reader scanning the
    /// list has no reason to be told which is which.
    enum Source: Hashable {
        case vault(path: String)
        case photo(id: PersistentIdentifier)
    }

    /// What a row shows, and how many were left out.
    ///
    /// The note's own pictures first: they were put there on purpose, where an
    /// outing's came with the sync.
    static func strip(of sources: [Source]) -> (shown: [Source], extra: Int) {
        (Array(sources.prefix(limit)), max(0, sources.count - limit))
    }

    /// The thumbnail for one source, decoded once.
    ///
    /// Nil for anything that will not read: a link to a picture the journal
    /// never held, a photo whose bytes never arrived. The row then shows one
    /// thumbnail fewer rather than an empty frame, because a list is scanned
    /// and a hole in it reads as a fault.
    static func image(
        for source: Source, folder: URL, context: ModelContext?
    ) -> NSImage? {
        switch source {
        case let .vault(path):
            let url = folder.appending(path: path)
            return cached("vault:\(url.path)") { thumbnail(from: CGImageSourceCreateWithURL(url as CFURL, nil)) }
        case let .photo(id):
            return cached("photo:\(id.hashValue)") {
                // `model(for:)` reads the context's own registry rather than
                // the disk: the photo is already there, the row only needs its
                // bytes. They are external storage, so this is the one moment
                // they are loaded — hence the cache above it.
                guard let photo = context?.model(for: id) as? ActivityPhoto,
                      let data = photo.data
                else { return nil }
                return thumbnail(from: CGImageSourceCreateWithData(data as CFData, nil))
            }
        }
    }

    private static func cached(
        _ key: String, _ make: () -> NSImage?
    ) -> NSImage? {
        if let hit = cache[key] { return hit }
        let image = make()
        cache[key] = image
        order.append(key)
        evictIfNeeded()
        return image
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
    private static func thumbnail(from source: CGImageSource?) -> NSImage? {
        guard let source,
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
    let sources: [JournalThumbnails.Source]
    let folder: URL

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let strip = JournalThumbnails.strip(of: sources)
        let images = strip.shown.compactMap {
            JournalThumbnails.image(for: $0, folder: folder, context: modelContext)
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
