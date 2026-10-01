import SwiftUI
import SwiftData

/// Les meilleurs efforts à pied : pour chaque distance, les trois meilleurs
/// temps de toute la bibliothèque.
///
/// Toute la bibliothèque et non la période : un record de l'an dernier reste
/// le record. Les autres filtres s'appliquent — « mes records sur route » se
/// lit en ne cochant que la course.
struct BestEffortsCard: View {
    /// Les sorties filtrées par la barre latérale, toutes dates confondues.
    let activities: [Activity]
    let onSelect: (PersistentIdentifier) -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        let byUUID = Dictionary(
            activities.lazy
                .filter { BestEfforts.sports.contains($0.sportType) }
                .map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let standings = app.bestEfforts.standings(among: Set(byUUID.keys))
        let distances = EffortDistance.allCases.filter { !standings.top($0).isEmpty }

        StatsCard(
            "Meilleurs efforts",
            subtitle: "Course et trail, toutes dates · les trois meilleurs temps"
        ) {
            if distances.isEmpty {
                Text(
                    app.bestEfforts.isReady
                        ? "Aucune sortie à pied avec sa trace détaillée dans ces filtres."
                        : "Calcul en cours…"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(distances) { distance in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(distance.label)
                                .font(.callout.weight(.medium))
                                .frame(minWidth: 96, alignment: .leading)
                            ForEach(Array(standings.top(distance).enumerated()), id: \.element.id) { index, entry in
                                if let activity = byUUID[entry.uuid] {
                                    EffortCell(
                                        rank: index + 1,
                                        distance: distance,
                                        entry: entry,
                                        activity: activity,
                                        onSelect: onSelect
                                    )
                                }
                            }
                        }
                        if distance != distances.last {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

/// Un temps sur le podium : la médaille, le temps, l'allure, le jour. Le tout
/// ouvre la sortie.
private struct EffortCell: View {
    let rank: Int
    let distance: EffortDistance
    let entry: EffortStandings.Entry
    let activity: Activity
    let onSelect: (PersistentIdentifier) -> Void

    var body: some View {
        Button {
            onSelect(activity.persistentModelID)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "medal.fill")
                    .font(.caption)
                    .foregroundStyle(EffortMedal.color(rank: rank))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.raceTime(entry.seconds))
                            .font(.body.monospacedDigit().weight(rank == 1 ? .semibold : .regular))
                        Text(Format.speed(distance.metres / entry.seconds, sport: .run))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(Format.dateOnly(activity.startDate, in: activity.timeZone))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 120, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("\(Format.rank(rank)) · « \(activity.name) »")
    }
}
