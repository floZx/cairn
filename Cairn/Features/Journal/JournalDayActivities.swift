import SwiftUI
import SwiftData

/// What the body did on the day the note is about — and what was written about
/// it at the time.
///
/// The activity's own note is the point of the block, not a garnish: one keeps
/// a journal to have "sensations, météo, matériel" from the evening of the run
/// in front of one while writing about the day. The figures are the reminder
/// that puts it in context.
///
/// A view of its own rather than a list handed down from `RootView`: the note's
/// pane rebuilds on every keystroke — the draft lives there — and re-filtering
/// the whole library per character would mean building a `DateKey` for each of
/// several hundred activities to compare it away again. Here the fetch is a
/// predicate on a date range, and it re-runs only when `date` changes.
///
/// Silent on a day with nothing: a heading announcing an empty list is worse
/// than no heading, and most days of a journal have no outing on them.
struct JournalDayActivities: View {
    let date: DateKey
    let onSelect: (PersistentIdentifier) -> Void

    /// Sizes, read against `JournalDetailView.noteSize` — the note this pane is
    /// for, at 15.
    ///
    /// The recap is secondary and should look it, but the first pass put it at
    /// 11 and 12 against that 15 and it read as fine print rather than as a
    /// lesser voice. One point under the note for what was written about the
    /// outing, two for the line that names it: enough of a step to rank them,
    /// not enough to make the block hard to read.
    private static let noteSize: CGFloat = 14
    private static let headingSize: CGFloat = 13
    /// Two thirds of the detail pane's, which is the ratio between the two
    /// panes: this one shares its width with a note.
    private static let photoHeight: CGFloat = 96

    @Query private var activities: [Activity]

    init(date: DateKey, onSelect: @escaping (PersistentIdentifier) -> Void) {
        self.date = date
        self.onSelect = onSelect
        let (start, end) = Self.dayRange(date)
        _activities = Query(
            filter: #Predicate<Activity> { $0.startDate >= start && $0.startDate < end },
            sort: \Activity.startDate
        )
    }

    /// The instants a calendar day spans, locally.
    ///
    /// Local midnight to local midnight, which is what `DateKey` means: an
    /// activity is filed under the day it started on, so a run at 23:40 belongs
    /// to that evening and one at 00:10 to the next morning. Going through
    /// `DateKey.advanced(by:)` rather than adding 86 400 seconds is what makes
    /// that hold across a daylight-saving change, where a day is 23 or 25
    /// hours long.
    static func dayRange(_ date: DateKey) -> (start: Date, end: Date) {
        (date.date(), date.advanced(by: 1).date())
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(activities.count > 1 ? "Activités du jour" : "Activité du jour")
                    .font(.system(size: Self.headingSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(activities) { activity in
                    entry(activity)
                }
            }
        }
    }

    private func entry(_ activity: Activity) -> some View {
        // The heading is the button, not the whole card: an activity's note can
        // run to a paragraph, and a click target that tall is one the pointer
        // falls into rather than one it aims at. It also leaves the note
        // selectable, which a button's label is not.
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onSelect(activity.persistentModelID)
            } label: {
                row(activity)
            }
            .buttonStyle(.plain)
            .help("Ouvrir « \(activity.name) » dans Mes activités")

            let note = Self.note(of: activity)
            if !note.isEmpty {
                MarkdownText(
                    markdown: note, baseSize: Self.noteSize, hidesTagHashes: true
                )
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            // The outing's own photos, under what was written about it —
            // clickable, as in its pane. Untitled and shorter here: the line
            // above already names the outing, and this block is a recap beside
            // a note rather than the page about the outing.
            ActivityPhotosStrip(
                activityUUID: activity.uuid, showsTitle: false,
                thumbnailHeight: Self.photoHeight
            )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 5))
    }

    /// The activity's own note, or empty when it has none worth showing.
    ///
    /// Trimmed before the emptiness test: a note left as a stray newline by an
    /// editor is a note with nothing in it, and a card opening on a blank line
    /// says less than one that never opened.
    static func note(of activity: Activity) -> String {
        activity.activityDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func row(_ activity: Activity) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // First, and on its own: the rows are in the order the day
            // happened, and the hour is what places each one in it — before
            // knowing what the outing was, one wants to know when it fell.
            // The instant, read in the zone the outing happened in: a run at
            // 06:52 in Paris is a run at 06:52 whether it is read from Paris
            // or from Nouméa.
            Text(Format.time(activity.startDate, in: activity.timeZone))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: activity.sportType.symbolName)
                .foregroundStyle(activity.sportType.color)
                // A gutter, so every name starts at the same place whatever
                // width the symbol happens to have.
                .frame(width: 16)
            Text(activity.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(Self.figures(
                distance: activity.distance,
                movingTime: activity.movingTime,
                elevation: activity.totalElevationGain
            ))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .font(.system(size: Self.headingSize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// Distance, time, climb — and the ones that would be a lie are left out.
    ///
    /// A swim has no climb worth printing and a gym session has no distance at
    /// all; a row of dashes says nothing that an absent figure does not say
    /// better, in a block whose whole point is to be read in passing.
    static func figures(
        distance: Double, movingTime: Int, elevation: Double
    ) -> String {
        var parts: [String] = []
        if distance > 0 { parts.append(Format.distance(distance)) }
        if movingTime > 0 { parts.append(Format.durationCompact(movingTime)) }
        if elevation > 0 { parts.append(Format.elevation(elevation)) }
        return parts.joined(separator: " · ")
    }
}
