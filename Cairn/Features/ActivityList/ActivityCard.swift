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

    /// Tall enough for two lines of figures beside a legible thumbnail, and
    /// fixed so nothing has to be measured. See the type's own note.
    static let height: CGFloat = 92
    private static let thumbnailWidth: CGFloat = 96

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: activity.sportType.symbolName)
                        .foregroundStyle(activity.sportType.color)
                    Text(activity.name)
                        .font(.headline)
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

                figures
            }

            Spacer(minLength: 0)
            photos
        }
        .padding(.vertical, 6)
        .frame(height: Self.height)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let coordinates = activity.simplifiedCoordinates
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.5))
            if coordinates.count > 1 {
                TrackThumbnail(coordinates: coordinates, color: activity.sportType.color)
            } else {
                // Indoor sessions have no track at all. The symbol says which
                // kind of nothing this is, rather than leaving an empty box that
                // reads as a failure to load.
                Image(systemName: activity.sportType.symbolName)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: Self.thumbnailWidth, height: Self.height - 16)
    }

    /// The four figures that answer "what was this outing", in one line.
    private var figures: some View {
        HStack(spacing: 10) {
            figure("figure.walk", Format.distance(activity.distance))
            figure("clock", Format.durationCompact(activity.movingTime))
            figure("arrow.up.right", Format.elevation(activity.totalElevationGain))
            if let heartrate = activity.averageHeartrate {
                figure("heart", Format.heartrate(heartrate))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func figure(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(value).monospacedDigit()
        }
    }

    /// A glimpse of the photos, when there are any.
    ///
    /// Three at most: past that the row is a gallery, and the point here is only
    /// to say that this outing was worth photographing.
    private var photos: some View {
        HStack(spacing: 4) {
            ForEach(activity.orderedPhotos.prefix(3)) { photo in
                if let image = photo.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: Self.height - 16)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }
        }
    }
}
