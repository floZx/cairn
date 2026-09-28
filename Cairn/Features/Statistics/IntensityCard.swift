import SwiftUI
import Charts

/// The period's time in heart-rate zones: the split, what kind of training it
/// makes, and how it went week by week.
struct IntensityCard: View {
    let intensity: Intensity
    let granularity: StatsGranularity

    private static let names = ["Échauffement", "Facile", "Aérobie", "Seuil", "Maximum"]

    var body: some View {
        StatsCard(
            "Intensité",
            subtitle: "Le temps passé dans chaque zone de fréquence cardiaque"
        ) {
            if intensity.total == 0 {
                Text("Aucune sortie de la période n'a de zones Garmin.")
                    .foregroundStyle(.secondary)
            } else {
                header
                split
                legend
                slotChart
                Text("\(intensity.covered) sorties sur \(intensity.count) ont des zones Garmin ; les autres ne comptent pas ici : une FC moyenne ne dit pas comment le temps s'est réparti.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            KeyFigure(title: "Facile · Z1–2", value: percent(intensity.easy), detail: hours(1...2))
            KeyFigure(title: "Modéré · Z3", value: percent(intensity.moderate), detail: hours(3...3))
            KeyFigure(title: "Intense · Z4–5", value: percent(intensity.hard), detail: hours(4...5))
            if let profile = intensity.profile {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Répartition").font(.caption).foregroundStyle(.secondary)
                    Text(profile.label).font(.title3.weight(.semibold))
                    Text(profile.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
            }
        }
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded())) %"
    }

    private func hours(_ zones: ClosedRange<Int>) -> String {
        let seconds = zones.reduce(0) { $0 + intensity.seconds[$1 - 1] }
        return Format.durationCompact(Int(seconds))
    }

    /// The five zones end to end on one bar: the proportions at a glance.
    private var split: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<Intensity.zoneCount, id: \.self) { index in
                    let share = intensity.seconds[index] / intensity.total
                    if share > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ActivityZonesView.color(zone: index + 1).opacity(0.8))
                            .frame(width: max(2, (geometry.size.width - 8) * share))
                            .overlay {
                                if share > 0.06 {
                                    Text("\(Int((share * 100).rounded())) %")
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }
            }
        }
        .frame(height: 18)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(0..<Intensity.zoneCount, id: \.self) { index in
                HStack(spacing: 5) {
                    Circle()
                        .fill(ActivityZonesView.color(zone: index + 1).opacity(0.8))
                        .frame(width: 7, height: 7)
                    Text("Z\(index + 1) \(Self.names[index])")
                        .foregroundStyle(.secondary)
                    Text(Format.durationCompact(Int(intensity.seconds[index])))
                        .monospacedDigit()
                }
            }
        }
        .font(.caption)
    }

    private struct Bar: Identifiable {
        let start: Date
        let zone: Int
        let hours: Double
        var id: String { "\(start.timeIntervalSinceReferenceDate)-\(zone)" }
    }

    private var bars: [Bar] {
        intensity.slots.flatMap { slot in
            slot.seconds.enumerated().map {
                Bar(start: slot.start, zone: $0.offset + 1, hours: $0.element / 3600)
            }
        }
    }

    /// Zone 1 at the bottom, like a pile: the easy base and what is stacked on
    /// it.
    private var slotChart: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Début", bar.start, unit: granularity.component),
                y: .value("Heures", bar.hours)
            )
            .foregroundStyle(by: .value("Zone", "Z\(bar.zone)"))
        }
        .chartForegroundStyleScale(
            domain: (1...5).map { "Z\($0)" },
            range: (1...5).map { ActivityZonesView.color(zone: $0).opacity(0.8) }
        )
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let raw = value.as(Double.self) { Text("\(Int(raw)) h") }
                }
            }
        }
        .frame(height: 160)
    }
}
