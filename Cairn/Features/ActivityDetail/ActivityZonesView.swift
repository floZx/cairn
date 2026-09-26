import SwiftUI

/// Les lignes d'un tableau de zones, à la façon de Garmin : zone 5 en haut,
/// sa plage, son nom, le temps passé et sa part.
enum ZoneTable {
    enum Kind {
        case heartRate, power

        var title: String {
            switch self {
            case .heartRate: "Zones de fréquence cardiaque"
            case .power: "Zones de puissance"
            }
        }

        var unit: String {
            switch self {
            case .heartRate: "bpm"
            case .power: "W"
            }
        }

        /// Les noms que Garmin donne à ses cinq zones, zone 1 d'abord.
        var names: [String] {
            switch self {
            case .heartRate: ["Échauffement", "Facile", "Aérobie", "Seuil", "Maximum"]
            case .power: ["Facile", "Modéré", "Tempo", "Intervalle long", "Intervalle court"]
            }
        }
    }

    struct Row: Equatable, Identifiable {
        let zone: Int
        let range: String
        let name: String
        let seconds: Double
        let share: Double
        var id: Int { zone }
        /// Tronqué, comme Garmin : 74,9 % s'y lit « 74 % ».
        var percent: Int { Int(share * 100) }
    }

    /// « 144 - 152 bpm » : de la borne basse de la zone à celle de la suivante
    /// moins un ; « > 166 bpm » pour la dernière. Zone 5 d'abord, comme Garmin.
    static func rows(floors: [Double], seconds: [Double], kind: Kind) -> [Row] {
        let count = min(floors.count, seconds.count)
        guard count > 0 else { return [] }
        let total = seconds.prefix(count).reduce(0, +)
        return (0..<count).reversed().map { i in
            let low = Int(floors[i].rounded())
            let range: String
            if i + 1 < count {
                range = "\(low) - \(Int(floors[i + 1].rounded()) - 1) \(kind.unit)"
            } else {
                range = "> \(low - 1) \(kind.unit)"
            }
            return Row(
                zone: i + 1,
                range: range,
                name: i < kind.names.count ? kind.names[i] : "",
                seconds: seconds[i],
                share: total > 0 ? seconds[i] / total : 0
            )
        }
    }

    /// « 35:07 », « 1:02:40 » — le temps d'une zone, à la seconde.
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let (h, m, r) = (s / 3600, (s % 3600) / 60, s % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, r)
            : String(format: "%d:%02d", m, r)
    }
}

/// Les zones de FC et de puissance d'une sortie, telles que Garmin les
/// appliquait ce jour-là. Rien du tout quand Garmin n'en avait pas.
struct ActivityZonesView: View {
    let activity: Activity
    /// FC ou puissance, retenu d'une sortie à l'autre : on compare les
    /// sorties sur la même mesure.
    @AppStorage("zonesShowPower") private var showsPower = false

    var body: some View {
        let heartRate = zip(activity.hrZoneFloors, activity.hrZoneSeconds)
        let power = zip(activity.powerZoneFloors, activity.powerZoneSeconds)
        // Une seule section, et le choix entre les deux quand les deux
        // existent : deux tableaux de cinq lignes l'un sous l'autre prenaient
        // la hauteur du volet — le téléphone l'a fait en premier.
        if heartRate != nil || power != nil {
            let showing: ZoneTable.Kind = power != nil && (showsPower || heartRate == nil)
                ? .power : .heartRate
            let data = showing == .power ? power! : heartRate!
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Zones").font(.headline)
                    Spacer()
                    if heartRate != nil, power != nil {
                        Picker("Zones", selection: $showsPower) {
                            Text("FC").tag(false)
                            Text("Puissance").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        Text(showing == .power ? "Puissance" : "FC")
                            .foregroundStyle(.secondary)
                    }
                }
                rows(ZoneTable.rows(floors: data.0, seconds: data.1, kind: showing))
            }
        }
    }

    private func zip(_ floors: [Double]?, _ seconds: [Double]?) -> ([Double], [Double])? {
        guard let floors, let seconds, !floors.isEmpty else { return nil }
        return (floors, seconds)
    }

    /// Les couleurs de Garmin, de la zone 1 à la 5 : gris, bleu, vert,
    /// orange, rouge.
    static func color(zone: Int) -> Color {
        switch zone {
        case 1: .gray
        case 2: .blue
        case 3: .green
        case 4: .orange
        default: .red
        }
    }

    private func rows(_ rows: [ZoneTable.Row]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Zone \(row.zone)").fontWeight(.semibold)
                        Text("\(row.range) · \(row.name)").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule()
                                    .fill(Self.color(zone: row.zone))
                                    .frame(width: geo.size.width * row.share)
                            }
                        }
                        .frame(height: 8)
                        Text(ZoneTable.duration(row.seconds))
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                        Text("\(row.percent) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }
}
