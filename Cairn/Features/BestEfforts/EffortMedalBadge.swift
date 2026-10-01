import SwiftUI
import SwiftData

extension EffortMedal {
    /// Or, argent, bronze — les couleurs d'une médaille, pas celles d'un sport.
    static func color(rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.93, green: 0.72, blue: 0.13)
        case 2: Color(red: 0.62, green: 0.65, blue: 0.70)
        default: Color(red: 0.76, green: 0.49, blue: 0.27)
        }
    }

    var color: Color { Self.color(rank: rank) }

    /// « 1er · 5 km en 21:34 »
    var summary: String {
        "\(Format.rank(rank)) · \(distance.label) en \(Format.raceTime(seconds))"
    }
}

/// La médaille d'une sortie qui tient une place sur un podium.
///
/// Une seule médaille même quand la sortie en détient plusieurs : la meilleure
/// place, avec le nombre de records à côté. Un clic ouvre les podiums.
struct EffortMedalBadge: View {
    let medals: [EffortMedal]
    /// La sortie qui porte la médaille, mise en avant dans les podiums.
    let uuid: String
    @State private var showsPodium = false

    private var best: EffortMedal? {
        medals.min { ($0.rank, $0.distance.rawValue) < ($1.rank, $1.distance.rawValue) }
    }

    var body: some View {
        if let best {
            Button { showsPodium.toggle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "medal.fill")
                        .foregroundStyle(best.color)
                    if medals.count > 1 {
                        Text("\(medals.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .popover(isPresented: $showsPodium, arrowEdge: .bottom) {
                EffortPodiumsView(
                    distances: medals.map(\.distance), highlighted: uuid,
                    onOpen: { showsPodium = false }
                )
            }
        }
    }

    private var tooltip: String {
        medals
            .sorted { $0.distance.rawValue < $1.distance.rawValue }
            .map(\.summary)
            .joined(separator: "\n")
    }
}

/// Les podiums de la sortie, en toutes lettres, sous les chiffres de la fiche.
/// Chaque pastille ouvre le podium de sa distance.
struct EffortMedalsRow: View {
    let medals: [EffortMedal]
    let uuid: String

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(medals.sorted { $0.distance.rawValue < $1.distance.rawValue }, id: \.self) { medal in
                EffortMedalChip(medal: medal, uuid: uuid)
            }
        }
    }
}

private struct EffortMedalChip: View {
    let medal: EffortMedal
    let uuid: String
    @State private var showsPodium = false

    var body: some View {
        Button { showsPodium.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "medal.fill").foregroundStyle(medal.color)
                Text(medal.distance.label).foregroundStyle(.secondary)
                Text(Format.raceTime(medal.seconds)).monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(medal.color.opacity(0.14), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("\(Format.rank(medal.rank)) meilleur temps sur \(medal.distance.label)")
        .popover(isPresented: $showsPodium, arrowEdge: .bottom) {
            EffortPodiumsView(
                distances: [medal.distance], highlighted: uuid,
                onOpen: { showsPodium = false }
            )
        }
    }
}

/// Le podium de chaque distance : les trois meilleurs temps, chacun avec la
/// sortie qui l'a couru. Un titre ouvre la sortie ; celle d'où l'on vient est
/// en gras, sans lien — on y est déjà.
struct EffortPodiumsView: View {
    let distances: [EffortDistance]
    let highlighted: String
    var onOpen: () -> Void = {}
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let standings = app.bestEfforts.standings
        let ordered = distances.sorted { $0.rawValue < $1.rawValue }
        let entries = ordered.flatMap { standings.top($0) }
        let activities = fetch(Set(entries.map(\.uuid)))

        VStack(alignment: .leading, spacing: 14) {
            ForEach(ordered) { distance in
                VStack(alignment: .leading, spacing: 6) {
                    Text(distance.label).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                        ForEach(Array(standings.top(distance).enumerated()), id: \.element.id) { index, entry in
                            row(rank: index + 1, distance: distance, entry: entry,
                                activity: activities[entry.uuid])
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 340, alignment: .leading)
        // Le premier lien prenait le focus à l'ouverture, encadré de bleu
        // comme s'il était déjà choisi.
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func row(
        rank: Int, distance: EffortDistance, entry: EffortStandings.Entry, activity: Activity?
    ) -> some View {
        let isHere = entry.uuid == highlighted
        GridRow(alignment: .firstTextBaseline) {
            Image(systemName: "medal.fill")
                .foregroundStyle(EffortMedal.color(rank: rank))
            Text(Format.raceTime(entry.seconds))
                .font(.body.monospacedDigit().weight(isHere ? .semibold : .regular))
            Text(Format.speed(distance.metres / entry.seconds, sport: .run))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let activity {
                VStack(alignment: .leading, spacing: 0) {
                    if isHere {
                        Text(activity.name).fontWeight(.semibold).lineLimit(1)
                    } else {
                        Button(activity.name) {
                            onOpen()
                            app.requestSelectActivity?(activity.persistentModelID)
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .help("Ouvrir « \(activity.name) »")
                    }
                    Text(Format.dateOnly(activity.startDate, in: activity.timeZone))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func fetch(_ uuids: Set<String>) -> [String: Activity] {
        let wanted = Array(uuids)
        let found = (try? modelContext.fetch(FetchDescriptor<Activity>(
            predicate: #Predicate { wanted.contains($0.uuid) }
        ))) ?? []
        return Dictionary(found.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
