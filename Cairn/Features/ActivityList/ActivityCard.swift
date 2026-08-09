import SwiftUI
import SwiftData

/// One activity as a card: its shape, its name, its figures.
///
/// Every card is the same height, and deliberately so. A list of rows that size
/// themselves makes AppKit build all 840 of them to measure — the ten-second
/// freeze on sorting the table came from exactly that. Uniform cards let the
/// same fixed-height probe apply here.
struct ActivityCard: View {
    let activity: Activity

    /// Half the original 84: the tall card showed a handful of outings where
    /// the point of a list is to scan many. Two lines of text and a thumbnail
    /// still fit, everything just speaks one size down. Fixed so nothing has
    /// to be measured — see the type's own note.
    static let height: CGFloat = 42
    private static let thumbnailWidth: CGFloat = 52
    private var inner: CGFloat { Self.height - 10 }

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Image(systemName: activity.sportType.symbolName)
                        .font(.subheadline)
                        .foregroundStyle(activity.sportType.color)
                    Text(activity.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if activity.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption2)
                    }
                    // The thumbnails themselves were too much beside a row of
                    // figures; the fact that there are any is still worth
                    // knowing, and one glyph says it without taking a column.
                    if !activity.photos.isEmpty {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                            .help(
                                activity.photos.count == 1
                                    ? "1 photo" : "\(activity.photos.count) photos"
                            )
                    }
                }
                Text(Format.longDate(activity.startLocalDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // A floor, and a high priority: the name is what identifies the
            // row, and "T…" identifies nothing. What gives way instead is the
            // last figure, chosen below.
            .frame(minWidth: 150, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 12)
            figures
        }
        .padding(.vertical, 5)
        .frame(height: Self.height)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let coordinates = activity.simplifiedCoordinates
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                    .font(.body)
                    .foregroundStyle(activity.sportType.color.opacity(0.35))
            }
        }
        .frame(width: Self.thumbnailWidth, height: inner)
        // The colour spills out of the thumbnail and onto the row, so the card
        // is lit by its sport rather than merely labelled with it. Narrower than
        // the detail pane's glow: a row is short, and the same radius would wash
        // over its neighbours instead of its own text.
        .ambientGlow(activity.sportType.color, cornerRadius: 6, blurRadius: 18)
    }

    /// The figures, as a row of blocks rather than a line of small grey text.
    ///
    /// Value above label, the value at reading size: four identical captions
    /// made the card say everything at the same volume, which is the same as
    /// saying nothing. Heart rate drops out when there is none rather than
    /// leaving a hole.
    private var figures: some View {
        // Everything here is fixed-width, so on a narrow pane something has to
        // give. `ViewThatFits` decides *which*, in order of what an outing is
        // actually about: the heart rate goes before the climb, and the climb
        // before the distance. Left to the layout engine, it was the name that
        // gave way instead.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                distanceBlock
                durationBlock
                elevationBlock
                heartrateBlock
            }
            HStack(spacing: 0) {
                distanceBlock
                durationBlock
                elevationBlock
            }
            HStack(spacing: 0) {
                distanceBlock
                durationBlock
            }
            distanceBlock
        }
    }

    private var distanceBlock: some View {
        block(Format.distance(activity.distance), "Distance")
    }
    private var durationBlock: some View {
        block(Format.durationCompact(activity.movingTime), "Durée")
    }
    private var elevationBlock: some View {
        block(Format.elevation(activity.totalElevationGain), "D+")
    }
    @ViewBuilder
    private var heartrateBlock: some View {
        if let heartrate = activity.averageHeartrate {
            block(Format.heartrate(heartrate), "FC moy.")
        }
    }

    private func block(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .lineLimit(1)
                // Rather than truncating: a number cut short reads as another
                // number, where a slightly smaller one reads as itself.
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(width: 72, alignment: .leading)
    }
}
