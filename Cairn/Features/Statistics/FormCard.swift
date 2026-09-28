import SwiftUI
import Charts

/// Fitness, fatigue and form over the period, with today's reading on top.
struct FormCard: View {
    /// The whole series; only the period's days are drawn.
    let points: [TrainingLoad.Point]
    let periodStart: Date?
    let estimatedCount: Int
    let count: Int

    @State private var selectedDay: Date?

    private var shown: [TrainingLoad.Point] {
        guard let periodStart else { return points }
        return points.filter { $0.day >= periodStart }
    }

    var body: some View {
        StatsCard(
            "Forme",
            subtitle: "Charge d'entraînement tirée des zones de fréquence cardiaque"
        ) {
            if let today = points.last {
                header(today)
                chart
                formChart
                footnote
            } else {
                Text("Pas encore de sortie à mesurer.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Today

    private func header(_ today: TrainingLoad.Point) -> some View {
        let reading = selectedPoint ?? today
        let state = TrainingLoad.state(of: reading)
        return HStack(alignment: .top, spacing: 24) {
            KeyFigure(
                title: "Forme",
                value: "\(Int(reading.fitness.rounded()))",
                detail: rampText
            )
            KeyFigure(
                title: "Fatigue",
                value: "\(Int(reading.fatigue.rounded()))",
                detail: "moyenne sur 7 jours"
            )
            KeyFigure(
                title: "Fraîcheur",
                value: signed(reading.form),
                detail: "forme − fatigue"
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedPoint.map { Format.dateOnly($0.day) } ?? "Aujourd'hui")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Self.color(of: state))
                Text(state.advice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
        }
    }

    private var rampText: String? {
        guard let ramp = TrainingLoad.ramp(of: points) else { return nil }
        if abs(ramp) < 0.5 { return "stable sur 7 jours" }
        return "\(signed(ramp)) en 7 jours"
    }

    private var selectedPoint: TrainingLoad.Point? {
        guard let selectedDay else { return nil }
        let calendar = ActivityStatistics.calendar
        return shown.first { calendar.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    static func color(of state: TrainingLoad.State) -> Color {
        switch state {
        case .fresh: .green
        case .neutral: .secondary
        case .productive: .blue
        case .overreaching: .orange
        case .detraining: .yellow
        }
    }

    // MARK: - Charts

    /// Fitness as a filled line, fatigue as a thinner one over it, and the
    /// day's load as faint bars underneath — what put the curves where they are.
    private var chart: some View {
        Chart {
            ForEach(shown) { point in
                if point.load > 0 {
                    BarMark(
                        x: .value("Jour", point.day, unit: .day),
                        y: .value("Charge", point.load)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.13))
                }
            }
            ForEach(shown) { point in
                AreaMark(
                    x: .value("Jour", point.day, unit: .day),
                    y: .value("Valeur", point.fitness),
                    series: .value("Série", "Forme")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
            ForEach(shown) { point in
                LineMark(
                    x: .value("Jour", point.day, unit: .day),
                    y: .value("Valeur", point.fitness),
                    series: .value("Série", "Forme")
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            }
            ForEach(shown) { point in
                LineMark(
                    x: .value("Jour", point.day, unit: .day),
                    y: .value("Valeur", point.fatigue),
                    series: .value("Série", "Fatigue")
                )
                .foregroundStyle(Color.purple.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
            if let selectedPoint {
                RuleMark(x: .value("Jour", selectedPoint.day, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
        }
        // The daily bars can reach far above the averages; clipping them to
        // the curves keeps the curves readable, and a bar that runs off the
        // top still says "a big day".
        .chartYScale(domain: 0...yCeiling)
        .chartXSelection(value: $selectedDay)
        .chartXAxis { monthAxis }
        .chartLegend(.hidden)
        .frame(height: 200)
        .clipped()
        .overlay(alignment: .topLeading) { legend }
    }

    private var yCeiling: Double {
        let high = shown.map { max($0.fitness, $0.fatigue) }.max() ?? 1
        return max(10, high * 1.15)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("Forme", Color.accentColor)
            legendItem("Fatigue", Color.purple.opacity(0.7))
            legendItem("Charge du jour", Color.secondary.opacity(0.25))
        }
        .font(.caption2)
        .padding(6)
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 3)
            Text(label).foregroundStyle(.secondary)
        }
    }

    /// Form on its own scale, under the curves: above zero rested, below it
    /// loaded. Its own chart because it crosses zero and the others do not.
    private var formChart: some View {
        Chart {
            RuleMark(y: .value("Zéro", 0))
                .foregroundStyle(Color.secondary.opacity(0.4))
            ForEach(shown) { point in
                AreaMark(
                    x: .value("Jour", point.day, unit: .day),
                    y: .value("Fraîcheur", point.form)
                )
                .foregroundStyle(Color.secondary.opacity(0.12))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Jour", point.day, unit: .day),
                    y: .value("Fraîcheur", point.form)
                )
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
            if let selectedPoint {
                RuleMark(x: .value("Jour", selectedPoint.day, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: 70)
        .overlay(alignment: .topLeading) {
            Text("Fraîcheur")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }

    private var monthAxis: some AxisContent {
        AxisMarks(values: .stride(by: .month)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month(.abbreviated))
        }
    }

    private var footnote: some View {
        Text(footnoteText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footnoteText: String {
        let base = "Charge d'une sortie : minutes dans chaque zone × numéro de la zone. Forme : moyenne sur 42 jours, fatigue : sur 7."
        guard estimatedCount > 0 else { return base }
        return base + " \(estimatedCount) sorties sur \(count) n'ont pas de zones Garmin : leur charge est estimée d'après la FC moyenne."
    }
}
