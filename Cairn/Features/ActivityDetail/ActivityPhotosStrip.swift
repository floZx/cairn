import SwiftUI
import SwiftData

/// The activity's photos, in a row, each opening full size.
///
/// A strip rather than a grid: the count is usually one to five, and a grid of
/// three would leave two empty cells on every activity that has any.
struct ActivityPhotosStrip: View {
    /// Queried rather than read off `activity.photos`.
    ///
    /// The sync writes them from another `ModelContext`, and the relationship on
    /// an activity the interface already holds does not come back refreshed: the
    /// photos reached the disk and the pane stayed empty until the next launch.
    /// A `@Query` re-runs on a store change, so they appear as they arrive.
    @Query private var photos: [ActivityPhoto]
    @State private var opened: ActivityPhoto?

    init(activityUUID: String) {
        _photos = Query(
            filter: #Predicate<ActivityPhoto> { $0.activityUUID == activityUUID },
            sort: [SortDescriptor(\ActivityPhoto.sortIndex)]
        )
    }

    /// Tall enough to recognise a summit or a finish line, short enough that the
    /// figures below stay on screen with it.
    private static let thumbnailHeight: CGFloat = 140

    var body: some View {
        // Its own emptiness is its business: the caller cannot know how many
        // photos there are without running the same query.
        if !photos.isEmpty { strip }
    }

    private var strip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos")
                .font(.headline)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        Button { opened = photo } label: {
                            thumbnail(photo)
                        }
                        .buttonStyle(.plain)
                        .help(photo.caption ?? "Ouvrir en grand")
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
        .sheet(item: $opened) { photo in
            FullSizePhoto(photo: photo) { opened = nil }
        }
    }

    @ViewBuilder
    private func thumbnail(_ photo: ActivityPhoto) -> some View {
        if let image = photo.nsImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: Self.thumbnailHeight)
                // Fixed height, free width: portrait and landscape shots sit in
                // the same row, and forcing a square would crop every one of them.
                .fixedSize(horizontal: true, vertical: false)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            // The row exists before its bytes do: the sync records the photo
            // first and downloads it after, and a failed download is retried on
            // the next pass rather than losing the photo entirely.
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 180, height: Self.thumbnailHeight)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct FullSizePhoto: View {
    let photo: ActivityPhoto
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let image = photo.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.callout)
                    .padding(8)
            }
            Divider()
            HStack {
                Spacer()
                Button("Fermer", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

extension ActivityPhoto: Identifiable {
    var id: String { uniqueID }

    /// The stored bytes as an image, or nil while they have yet to arrive.
    var nsImage: NSImage? {
        data.flatMap(NSImage.init(data:))
    }
}
