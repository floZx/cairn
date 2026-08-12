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
    /// The insets the list wraps each card in — ours, not the `List` default,
    /// so the full row height is a constant the row-height probe can be told
    /// instead of having to measure (and mis-measure — see the probe).
    static let rowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    static var rowHeight: CGFloat { height + rowInsets.top + rowInsets.bottom }
    /// Was 52 × 32. A trace is a shape to recognise, not a map to read, and at
    /// the old size it was the loudest thing in a row whose subject is the name
    /// and the figures. The two are tuned together: the box keeps roughly its
    /// proportions, and the glyph that stands in for a missing trace is derived
    /// from the width rather than fixed, so one number moves the whole thing.
    private static let thumbnailWidth: CGFloat = 44
    private var inner: CGFloat { Self.height - 14 }

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    // No sport glyph here: the thumbnail to the left already
                    // says which sport this was, by the colour of its trace or
                    // by the symbol standing in for one, and repeating it
                    // beside the name only ate into the name.
                    Text(activity.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
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
                HStack(spacing: 4) {
                    Text(Format.longDate(activity.startDate, in: activity.timeZone))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // Symbols only, and after the date rather than beside the
                    // name: the favourite's star used to sit up there alone,
                    // and one marker shown out of six is a marker that lies by
                    // omission. Priority to the chips — a truncated date is
                    // still a date, a truncated row of markers is a wrong one.
                    ForEach(activity.labels) { label in
                        ActivityLabelChip(label: label, compact: true)
                    }
                    .layoutPriority(1)
                }
            }
            // A low floor and no priority: the figures are what the row is
            // read for, and a name cut short is still a name where a missing
            // heart rate is a row that quietly says less than its neighbour.
            // So this is what gives way, down to an ellipsis if it must.
            .frame(minWidth: 60, alignment: .leading)

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
            // No tile under the track: the tinted rectangle made sense on an
            // opaque list, where it lifted the trace off flat grey. Over the
            // frosted column it reads as a sticker on glass, and the trace
            // stands on its own — the glow below still lights the row.
            if coordinates.count > 1 {
                TrackThumbnail(coordinates: coordinates, color: activity.sportType.color)
            } else {
                // Indoor sessions have no track at all. The symbol says which
                // kind of nothing this is, rather than leaving an empty box that
                // reads as a failure to load.
                Image(systemName: activity.sportType.symbolName)
                    // Sized against the space a trace would have filled, not
                    // against the text: it stands in for the whole thumbnail,
                    // and at body size it was a small mark adrift in it. Now
                    // that the name carries no glyph of its own, this is what
                    // says which sport a gym session was. A fraction of the
                    // width so it follows whenever that is tuned.
                    .font(.system(size: Self.thumbnailWidth * 0.42))
                    // A touch stronger than it was: it used to sit on a tinted
                    // tile that framed it, and without one at the old opacity
                    // a gym session's grey glyph all but vanished.
                    .foregroundStyle(activity.sportType.color.opacity(0.5))
            }
        }
        .frame(width: Self.thumbnailWidth, height: inner)
        // The colour spills out of the thumbnail and onto the row, so the card
        // is lit by its sport rather than merely labelled with it. Narrower than
        // the detail pane's glow: a row is short, and the same radius would wash
        // over its neighbours instead of its own text.
        .ambientGlow(activity.sportType.color, cornerRadius: 6, blurRadius: 18)
    }

    /// The figures, one line, no labels.
    ///
    /// The labels went because every value already carries its unit: "9,0 km"
    /// under a caption reading "Distance" said the same thing twice, twenty
    /// times down a list, and cost half the height of the card. The eye now
    /// runs down a column of figures instead of re-reading four words.
    ///
    /// All five, always, in the same order. They used to drop out one by one
    /// through a `ViewThatFits` as the pane narrowed, which made two rows side
    /// by side carry different columns — the reader cannot tell a figure
    /// withheld for want of room from one the activity never recorded. The
    /// name absorbs the shortfall instead; see its frame above.
    private var figures: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.figures(for: activity).enumerated()), id: \.offset) {
                _, figure in
                Text(figure.value ?? "")
                    // Emphasis by weight alone: over twenty rows it is enough
                    // to bring out the month's three long outings, where a
                    // larger body would break the alignment of the columns and
                    // shout.
                    .font(
                        .subheadline
                            .weight(figure.isLeading ? .semibold : .regular)
                            .monospacedDigit()
                    )
                    .lineLimit(1)
                    // Rather than truncating: a number cut short reads as
                    // another number, where a slightly smaller one reads as
                    // itself.
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.columnWidth, alignment: .leading)
            }
        }
    }

    /// Five columns where there were four, and no labels under them: each one
    /// gives up a little width, and the name gains what is left over.
    private static let columnWidth: CGFloat = 62
}

extension ActivityCard {
    /// One column of the figures row. `nil` where the activity has no such
    /// measurement — an empty column, never a zero: a gym session has no
    /// distance, which is not the same as having a distance of zero.
    struct Figure: Equatable {
        var value: String?
        /// True on the first figure actually written, and only on a notable
        /// outing. See `isNotable`.
        var isLeading = false
    }

    /// What makes an outing stand out in a list of twenty.
    ///
    /// Two thresholds and not one, because one sport is not measured like
    /// another: three hours of cycling and 25 km of trail are both an outing
    /// one remembers, an hour of jogging is not. Written side by side so that
    /// moving the line takes a second.
    static let notableMovingTime = 90 * 60
    static let notableDistance: Double = 20_000

    static func isNotable(_ activity: Activity) -> Bool {
        activity.movingTime >= notableMovingTime
            || activity.distance >= notableDistance
    }

    /// The five columns, always in the same order, so two neighbouring rows
    /// line up whatever they carry.
    static func figures(for activity: Activity) -> [Figure] {
        var values: [String?] = [
            activity.distance > 0 ? Format.distance(activity.distance) : nil,
            // The one measurement an activity always has.
            Format.durationCompact(activity.movingTime),
            activity.totalElevationGain > 0
                ? Format.elevation(activity.totalElevationGain) : nil,
            activity.averageSpeed > 0
                ? Format.speed(activity.averageSpeed, sport: activity.sportType)
                : nil,
            activity.averageHeartrate.map(Format.heartrate),
        ]
        // `Format.heartrate` answers with a dash for the zero Strava sends on
        // some manual entries; here that means the column is simply empty.
        if values[4] == "—" { values[4] = nil }

        var figures = values.map { Figure(value: $0) }
        if isNotable(activity),
           let first = figures.firstIndex(where: { $0.value != nil }) {
            figures[first].isLeading = true
        }
        return figures
    }
}
