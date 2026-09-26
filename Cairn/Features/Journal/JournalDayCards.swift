import SwiftUI
import SwiftData

/// What the day did, as cards under the day's heading — one per outing, one
/// per meal that says something — in the style of the gear and weather cards
/// of an activity's pane.
///
/// An outing's card also holds what was written about it and its pictures.
///
/// They replace the « Activités du jour » and « Alimentation du jour » blocks
/// and the full-width rule under them: the same facts, in the vocabulary the
/// activity pane already speaks.
struct JournalDayCards: View {
    let date: DateKey
    let onSelectActivity: (PersistentIdentifier) -> Void
    let onSelectDay: (DateKey) -> Void
    let onSelectWeight: () -> Void

    @Query private var activities: [Activity]
    @Query private var mealNotes: [MealNote]
    @Query private var weights: [WeightEntry]

    init(
        date: DateKey,
        onSelectActivity: @escaping (PersistentIdentifier) -> Void,
        onSelectDay: @escaping (DateKey) -> Void,
        onSelectWeight: @escaping () -> Void
    ) {
        self.date = date
        self.onSelectActivity = onSelectActivity
        self.onSelectDay = onSelectDay
        self.onSelectWeight = onSelectWeight
        let (start, end) = JournalDayActivities.dayRange(date)
        _activities = Query(
            filter: #Predicate<Activity> { $0.startDate >= start && $0.startDate < end },
            sort: \Activity.startDate
        )
        let raw = date.raw
        _mealNotes = Query(filter: #Predicate<MealNote> { $0.dateKeyRaw == raw })
        _weights = Query(filter: #Predicate<WeightEntry> { $0.dateKeyRaw == raw })
    }

    var body: some View {
        let meals = JournalDayNutrition.spokenMeals(among: mealNotes)
        let weight = SidebarItem.weight.estMasquee
            ? nil : JournalDayNutrition.spokenWeight(among: weights)
        VStack(alignment: .leading, spacing: 8) {
            // One card per outing, holding what was written about it and its
            // pictures: a first set of cards naming the outings, then the same
            // outings again with their words under them, read as a repeat.
            ForEach(activities) { activity in
                activityCard(activity)
            }
            if !meals.isEmpty || weight != nil {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(meals) { meal in
                        Button { onSelectDay(date) } label: {
                            compactCard(
                                glyph("fork.knife"),
                                title: Text(JournalDayNutrition.label(for: meal)),
                                subtitle: MarkdownText.inline(
                                    JournalRowLayout.prose(of: JournalDayNutrition.note(of: meal)),
                                    hidingTagHashes: true
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Ouvrir dans Alimentation")
                    }
                    if let weight {
                        Button(action: onSelectWeight) {
                            compactCard(
                                glyph("scalemass"),
                                title: Text(JournalDayNutrition.weightLine(weight)),
                                subtitle: Text(JournalRowLayout.prose(of: JournalDayNutrition.note(of: weight)))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Ouvrir dans Poids")
                    }
                }
            }
        }
    }

    /// The outing's name and figures, then — when there are some — its words
    /// and pictures, in the same card. Only the heading opens the activity:
    /// the words stay selectable and their mentions clickable.
    private func activityCard(_ activity: Activity) -> some View {
        let note = JournalDayActivities.note(of: activity)
        let hasPhotos = (activity.photoCount ?? 0) > 0
        return VStack(alignment: .leading, spacing: 8) {
            Button { onSelectActivity(activity.persistentModelID) } label: {
                heading(
                    SportDot(sport: activity.sportType, size: 26),
                    title: Text(activity.name),
                    subtitle: Text(Self.figures(of: activity))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Ouvrir « \(activity.name) » dans Mes activités")
            if !note.isEmpty {
                MarkdownText(markdown: note, baseSize: 14, hidesTagHashes: true)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 37)
            }
            if hasPhotos {
                ActivityPhotosStrip(activityUUID: activity.uuid, showsTitle: false, thumbnailHeight: 80)
                    .padding(.leading, 37)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: JournalDetailView.textWidth, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }

    private func heading(_ leading: some View, title: Text, subtitle: Text) -> some View {
        HStack(spacing: 11) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                subtitle
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func compactCard(_ leading: some View, title: Text, subtitle: Text) -> some View {
        heading(leading, title: title, subtitle: subtitle)
            .frame(maxWidth: 320, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
    }

    /// « 07:14 · 9,1 km · 49 min · 19 m » — when, then how far and how long.
    static func figures(of activity: Activity) -> String {
        let when = Format.time(activity.startDate, in: activity.timeZone)
        let figures = JournalDayActivities.figures(
            distance: activity.distance,
            movingTime: activity.movingTime,
            elevation: activity.totalElevationGain
        )
        return figures.isEmpty ? when : "\(when) · \(figures)"
    }
}
