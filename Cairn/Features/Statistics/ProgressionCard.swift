import SwiftUI
import SwiftData
import Charts

/// One sport over the period: every outing as a point, the trend through
/// them, the sport's records and its gear.
struct ProgressionCard: View {
    let activities: [Activity]
    let sports: [SportType]
    let periodStart: Date
    let onSelect: (PersistentIdentifier) -> Void

    /// Remembered by name, so a period without that sport falls back to the
    /// first one rather than showing nothing.
    @AppStorage("statsProgressionSport") private var storedSport = ""
    @State private var measure: SportProgress.Measure = .speed
    @State private var hoveredDay: Date?
    @Environment(\.modelContext) private var modelContext

    private var sport: SportType? {
        sports.first { $0.rawValue == storedSport } ?? sports.first
    }

    var body: some View {
        StatsCard(
            "Progression",
            subtitle: "Chaque sortie de la période, et la tendance qui les traverse"
        ) {
            if let sport {
                Picker("Sport", selection: Binding(
                    get: { sport },
                    set: { storedSport = $0.rawValue }
                )) {
                    ForEach(sports, id: \.self) { sport in
                        Text(sport.displayName).tag(sport)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        } content: {
            if let sport {
                content(SportProgress.compute(
                    activities, sport: sport, since: periodStart,
                    gearDistances: SportProgress.gearDistances(in: modelContext)
                ))
            } else {
                Text("Pas assez de sorties d'un même sport sur la période.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ progress: SportProgress) -> some View {
        Picker("Mesure", selection: $measure) {
            ForEach(SportProgress.Measure.allCases) { measure in
                Text(measure.label(for: progress.sport)).tag(measure)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()

        figures(progress)
        chart(progress)
        Text(note(progress.sport))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Records de tous les temps").font(.subheadline.weight(.semibold))
                ForEach(progress.records) { record in
                    RecordRow(record: record, onSelect: onSelect)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !progress.gear.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Matériel").font(.subheadline.weight(.semibold))
                    ForEach(progress.gear) { gear in
                        HStack(alignment: .firstTextBaseline) {
                            Text(gear.name).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.distance(gear.totalDistance))
                                .monospacedDigit()
                            Text("· \(gear.count) sortie\(gear.count > 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Distance de toutes les sorties faites avec, recalculée dans Cairn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
    }

    // MARK: - Figures

    private func figures(_ progress: SportProgress) -> some View {
        let values = progress.points.compactMap { $0.value(measure) }
        let mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let trend = progress.trend(measure)
        let hovered = hoveredPoint(progress)
        return HStack(alignment: .top, spacing: 24) {
            KeyFigure(
                title: hovered.map { Format.dateOnly($0.day) } ?? "Moyenne",
                value: (hovered?.value(measure) ?? mean).map { format($0, progress.sport) } ?? "—",
                detail: hovered?.name ?? "\(values.count) sorties"
            )
            if let trend {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tendance").font(.caption).foregroundStyle(.secondary)
                    Text("\(format(trend.start.value, progress.sport)) → \(format(trend.end.value, progress.sport))")
                        .font(.title.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    trendBadge(trend)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func trendBadge(_ trend: SportProgress.Trend) -> some View {
        let change = trend.change
        let better = measure.higherIsBetter ? change > 0 : change < 0
        let flat = abs(change) < 1
        return HStack(spacing: 4) {
            Text((change > 0 ? "↑ " : change < 0 ? "↓ " : "") + "\(Int(abs(change).rounded())) %")
                .fontWeight(.semibold)
                .foregroundStyle(flat ? .secondary : better ? Color.green : Color.orange)
            Text(flat ? "stable sur la période" : better ? "en progrès sur la période" : "en recul sur la période")
                .foregroundStyle(.tertiary)
        }
        .font(.caption.monospacedDigit())
    }

    private func format(_ value: Double, _ sport: SportType) -> String {
        switch measure {
        case .speed: Format.speed(value, sport: sport)
        case .heartrate: "\(Int(value.rounded())) bpm"
        case .efficiency:
            "\(value.formatted(.number.precision(.fractionLength(2)))) m/batt."
        }
    }

    private func note(_ sport: SportType) -> String {
        var text = measure == .efficiency
            ? "Efficacité : mètres parcourus par battement de cœur. Elle monte quand on va plus vite pour le même effort — le vrai signe d'une forme qui progresse."
            : measure == .heartrate
                ? "FC moyenne de chaque sortie : plus basse à allure égale, c'est bon signe."
                : "Chaque point est une sortie ; survoler pour la voir, cliquer pour l'ouvrir."
        if SportProgress.usesEffortDistance(sport), measure != .heartrate {
            text += " En km-effort : 100 m de D+ comptent pour 1 km, sans quoi une sortie en montagne paraîtrait lente."
        }
        return text
    }

    // MARK: - Chart

    private func hoveredPoint(_ progress: SportProgress) -> SportProgress.Point? {
        guard let hoveredDay else { return nil }
        return progress.points
            .filter { $0.value(measure) != nil }
            .min { abs($0.day.timeIntervalSince(hoveredDay)) < abs($1.day.timeIntervalSince(hoveredDay)) }
    }

    private func chart(_ progress: SportProgress) -> some View {
        let points = progress.points.filter { $0.value(measure) != nil }
        let hovered = hoveredPoint(progress)
        let trend = progress.trend(measure)
        let values = points.compactMap { $0.value(measure) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.1, high * 0.02)
        return Chart {
            ForEach(points) { point in
                PointMark(
                    x: .value("Jour", point.day, unit: .day),
                    y: .value("Valeur", point.value(measure) ?? 0)
                )
                .foregroundStyle(Color.accentColor.opacity(point.id == hovered?.id ? 1 : 0.55))
                .symbolSize(point.id == hovered?.id ? 90 : 36)
            }
            if let trend {
                LineMark(x: .value("Jour", trend.start.day), y: .value("Valeur", trend.start.value),
                         series: .value("Série", "Tendance"))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                LineMark(x: .value("Jour", trend.end.day), y: .value("Valeur", trend.end.value),
                         series: .value("Série", "Tendance"))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXSelection(value: $hoveredDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let raw = value.as(Double.self) { Text(format(raw, progress.sport)) }
                }
            }
        }
        // Beside the hover selection rather than over it: an overlay would
        // take the pointer from the chart, and the hover with it.
        .simultaneousGesture(TapGesture().onEnded {
            if let hovered { onSelect(hovered.activityID) }
        })
        .frame(height: 220)
    }
}
