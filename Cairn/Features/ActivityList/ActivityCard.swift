import SwiftUI
import SwiftData

/// One activity as a card: its shape, its name, its figures.
///
/// Laid out the way Mail lays out a message — three stacked lines rather than
/// a row of columns: the name with the date at its end, the figures, then the
/// note. Columns reserved 4 × 72 pt for the figures before the name got a
/// point, so a narrow list cut the name and the date down to nothing; stacked,
/// every line takes the width there is.
///
/// Every card is the same height, and deliberately so. A list of rows that size
/// themselves makes AppKit build all 840 of them to measure — the ten-second
/// freeze on sorting the table came from exactly that. Uniform cards let the
/// same fixed-height probe apply here.
struct ActivityCard: View {
    let activity: Activity
    @AppStorage(ActivityCardThumbnail.storageKey)
    private var thumbnailStyle: ActivityCardThumbnail = .trace

    /// Three lines of text, where there were two at 42. Fixed so nothing has
    /// to be measured — see the type's own note.
    static let height: CGFloat = 52
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
    /// The thumbnail keeps the height it had beside two lines: the trace is a
    /// mark to recognise, and a taller box would only make it louder.
    private var inner: CGFloat { 28 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch thumbnailStyle {
            case .trace:
                thumbnail
                    .padding(.top, 2)
            case .traceAvatar:
                traceAvatar
                    .padding(.top, 3)
            case .avatar:
                avatar
                    .padding(.top, 3)
            case .avatarMono:
                avatar(tint: .accentColor)
                    .padding(.top, 3)
            case .dateTile:
                // La tuile du journal : le jour de la sortie, là où elle a eu
                // lieu — une course du soir à New York reste celle du 12.
                // L'heure sous la date, en petit : la tuile dit quand, entière.
                VStack(spacing: 0) {
                    JournalDateTile(date: localDay)
                    Text(Format.time(activity.startDate, in: activity.timeZone))
                        .font(.system(size: 8.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .none:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // No sport glyph here while there is a thumbnail: it
                    // already says which sport this was, and repeating it
                    // beside the name only ate into the name.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        // With no thumbnail, something still has to say which
                        // sport this was: the symbol, small and in the text's
                        // own colour, before the name.
                        if thumbnailStyle == .none {
                            Image(systemName: activity.sportType.symbolName)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        Text(activity.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    // Short and relative, as Mail heads a message: the full
                    // date was the widest thing in the row and said the least.
                    // The full one is still there on hover.
                    // Rien ici avec la tuile de date : le jour et l'heure y sont.
                    if thumbnailStyle != .dateTile {
                        Text(Format.relativeDate(activity.startDate, in: activity.timeZone))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .help(Format.longDate(activity.startDate, in: activity.timeZone))
                    }
                    // Avec la tuile de date, le sport en pastille au bout de la
                    // ligne, comme les marques d'une journée du journal.
                    if thumbnailStyle == .dateTile {
                        // Les marques rejoignent la pastille sur une seule
                        // ligne : empilées sous elle, elles tombaient de
                        // travers — signalé.
                        markers
                        SportDot(sport: activity.sportType, size: 16)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(figures.joined(separator: " · "))
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if thumbnailStyle != .dateTile { markers }
                }

                // What Mail gives to the first words of a message. Left empty
                // rather than filled with something for the sake of it: the
                // height is fixed anyway, and a blank line reads as "nothing
                // written", which is true.
                Text(preview ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .frame(height: Self.height, alignment: .top)
    }

    /// Le jour de la sortie dans son propre fuseau.
    private var localDay: DateKey {
        var calendar = Calendar.current
        calendar.timeZone = activity.timeZone ?? .current
        return DateKey(activity.startDate, calendar: calendar)
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

    /// The sport alone, in a round badge: Mail's face at the head of a
    /// message. Tinted rather than filled — a column of solid discs down the
    /// list would outshout the names beside them.
    private var avatar: some View { avatar(tint: activity.sportType.color) }

    /// The same badge in one colour for every sport — the system accent, blue
    /// unless changed in the macOS settings. The symbol alone tells the sports
    /// apart, and the list reads as one calm column rather than a palette.
    private func avatar(tint color: Color) -> some View {
        Image(systemName: activity.sportType.symbolName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .background(color.opacity(0.14), in: .circle)
    }

    private static let avatarSize: CGFloat = 32

    /// The shape of the outing inside the same round badge — the trace's
    /// recognisability with the avatar's calm, one column of discs. The sport
    /// symbol stands in when there is no track, as it does in `thumbnail`.
    @ViewBuilder
    private var traceAvatar: some View {
        let coordinates = activity.simplifiedCoordinates
        if coordinates.count > 1 {
            let color = activity.sportType.color
            TrackThumbnail(coordinates: coordinates, color: color)
                // Inset so the stroke stays clear of the curve of the disc: a
                // track reaching the edge of a circle reads as cut off.
                .padding(5)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .background(color.opacity(0.14), in: .circle)
        } else {
            avatar
        }
    }

    /// Photos and labels as bare symbols at the end of the figures, where Mail
    /// puts its paperclip: known at a glance, and out of the way of the text.
    /// The names move to the tooltips — these symbols are learned in a day,
    /// but not in a second.
    private var markers: some View {
        HStack(spacing: 5) {
            if !activity.photos.isEmpty {
                Image(systemName: "photo")
                    .help(
                        activity.photos.count == 1
                            ? "1 photo" : "\(activity.photos.count) photos"
                    )
            }
            ForEach(activity.labels) { label in
                Image(systemName: label.symbolName)
                    .foregroundStyle(
                        label == .favorite
                            ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary)
                    )
                    .help(label.displayName)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        // The markers win over the figures: a figure cut short still ends in
        // an ellipsis that says so, a missing marker says nothing at all.
        .fixedSize()
    }

    /// The first line of the note: what there is to read about the outing
    /// beyond its numbers. Not the gear in its absence — tried, and Strava's
    /// guess at which shoes were worn is too often wrong to print on every row.
    private var preview: String? {
        let note = activity.activityDescription?
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let note, !note.isEmpty else { return nil }
        return note
    }

    /// The figures the sport is read by, with their units and without labels:
    /// « 8,5 km · 47 min · 5:32/km · 137 bpm ». The unit already says which is
    /// which, and four captions under four numbers on every row was most of
    /// what made the list heavy.
    ///
    /// Chosen by sport, not by the room there is. Figures used to drop out one
    /// by one as the pane narrowed, and two rows side by side then carried
    /// different columns; here there are no columns to compare down, and two
    /// runs always show the same four things.
    private var figures: [String] {
        let sport = activity.sportType
        var parts: [String] = []
        if activity.distance > 0 {
            parts.append(Format.distance(activity.distance))
        }
        parts.append(Format.durationCompact(activity.movingTime))
        switch sport {
        // On the road, pace is the figure; the climb is noise.
        case .run, .swim, .rowing:
            if let pace = pace { parts.append(pace) }
        case .workout, .other:
            break
        default:
            parts.append("\(Format.elevation(activity.totalElevationGain)) D+")
        }
        if let heartrate = activity.averageHeartrate, heartrate > 0 {
            parts.append(Format.heartrate(heartrate))
        }
        // A gym session has no distance, pace or climb: its calories are what
        // is left to tell one from another.
        if sport == .workout || sport == .other,
           let calories = activity.calories, calories > 0 {
            parts.append(Format.calories(calories))
        }
        return parts
    }

    private var pace: String? {
        let speed = activity.averageSpeed > 0
            ? activity.averageSpeed
            : (activity.movingTime > 0 ? activity.distance / Double(activity.movingTime) : 0)
        guard speed > 0 else { return nil }
        return Format.speed(speed, sport: activity.sportType)
    }
}
