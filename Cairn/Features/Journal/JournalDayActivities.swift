import SwiftUI
import SwiftData

/// What the body did on the day the note is about.
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
                ForEach(activities) { activity in
                    Button {
                        onSelect(activity.persistentModelID)
                    } label: {
                        row(activity)
                    }
                    .buttonStyle(.plain)
                    .help("Ouvrir « \(activity.name) » dans Mes activités")
                }
            }
        }
    }

    private func row(_ activity: Activity) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
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
        .font(.caption)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 5))
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
