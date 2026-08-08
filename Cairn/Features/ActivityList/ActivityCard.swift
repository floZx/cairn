import SwiftUI
import SwiftData

/// One activity as a card: its shape, its name, its figures, its photos.
///
/// Every card is the same height, and deliberately so. A list of rows that size
/// themselves makes AppKit build all 840 of them to measure — the ten-second
/// freeze on sorting the table came from exactly that. Uniform cards let the
/// same fixed-height probe apply here.
struct ActivityCard: View {
    let activity: Activity

    /// Tall enough for a legible thumbnail and a row of figures at reading size.
    /// Fixed so nothing has to be measured — see the type's own note.
    static let height: CGFloat = 108
    private static let thumbnailWidth: CGFloat = 124
    private var inner: CGFloat { Self.height - 16 }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: activity.sportType.symbolName)
                        .font(.title3)
                        .foregroundStyle(activity.sportType.color)
                    Text(activity.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if activity.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
                Text(Format.longDate(activity.startLocalDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Yields its width before the figures do: a truncated name is
            // readable, a truncated number is a different number.
            .layoutPriority(1)

            Spacer(minLength: 12)
            figures
            photos
        }
        .padding(.vertical, 8)
        .frame(height: Self.height)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let coordinates = activity.simplifiedCoordinates
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                // Tinted by the sport rather than plain grey, the same language
                // the detail pane's glow already speaks.
                .fill(activity.sportType.color.opacity(0.10))
            if coordinates.count > 1 {
                TrackThumbnail(coordinates: coordinates, color: activity.sportType.color)
            } else {
                // Indoor sessions have no track at all. The symbol says which
                // kind of nothing this is, rather than leaving an empty box that
                // reads as a failure to load.
                Image(systemName: activity.sportType.symbolName)
                    .font(.title)
                    .foregroundStyle(activity.sportType.color.opacity(0.35))
            }
        }
        .frame(width: Self.thumbnailWidth, height: inner)
    }

    /// The figures, as a row of blocks rather than a line of small grey text.
    ///
    /// Value above label, the value at reading size: four identical captions
    /// made the card say everything at the same volume, which is the same as
    /// saying nothing. Heart rate drops out when there is none rather than
    /// leaving a hole.
    private var figures: some View {
        HStack(spacing: 0) {
            block(Format.distance(activity.distance), "Distance")
            block(Format.durationCompact(activity.movingTime), "Durée")
            block(Format.elevation(activity.totalElevationGain), "D+")
            if let heartrate = activity.averageHeartrate {
                block(Format.heartrate(heartrate), "FC moy.")
            }
        }
    }

    private func block(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                // Rather than truncating: a number cut short reads as another
                // number, where a slightly smaller one reads as itself.
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(width: 84, alignment: .leading)
    }

    /// A glimpse of the photos, when there are any.
    ///
    /// Three at most: past that the row is a gallery, and the point here is only
    /// to say that this outing was worth photographing.
    private var photos: some View {
        HStack(spacing: 5) {
            ForEach(activity.orderedPhotos.prefix(3)) { photo in
                if let image = photo.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 68, height: inner)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
    }
}
