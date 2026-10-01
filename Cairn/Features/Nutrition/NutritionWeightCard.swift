// Cairn/Features/Nutrition/NutritionWeightCard.swift
import SwiftUI
import Charts

/// The window of the weight chart on the nutrition screen, remembered.
enum NutritionWeightPeriod: String, CaseIterable, Identifiable {
    case threeMonths
    case sixMonths
    case year

    static let storageKey = "nutritionWeightPeriod"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .threeMonths: "3 mois"
        case .sixMonths: "6 mois"
        case .year: "1 an"
        }
    }

    var days: Int {
        switch self {
        case .threeMonths: 91
        case .sixMonths: 182
        case .year: 365
        }
    }
}

/// The weight beside the calories: the weigh-in of the day the screen shows
/// and its note — where one is added, edited or deleted — how far the trend
/// moved over the window, and the line. A point clicked on
/// the line moves the whole screen to its day.
struct NutritionWeightCard: View {
    /// Ascending by date.
    let points: [WeightPoint]
    let day: DateKey
    /// The weigh-in of `day`, if there is one.
    let dayEntry: WeightEntry?
    let onSelectDay: (DateKey) -> Void
    let onEditDay: () -> Void
    let onDeleteDay: () -> Void

    @AppStorage(NutritionWeightPeriod.storageKey)
    private var period: NutritionWeightPeriod = .threeMonths
    @State private var hoveredDate: Date?

    var body: some View {
        // Anchored on the last weigh-in: a scale left unused for a month
        // still shows a line, not an empty frame.
        let windowed = WeightStats.window(points, days: period.days)
        // Smoothed over the whole history, then cut: the window's first days
        // keep the week before them in their mean.
        let trend = WeightStats.window(WeightStats.trend(points), days: period.days)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Poids").font(.caption).foregroundStyle(.secondary)
                Spacer()
                periodPicker
            }
            figureRow(trend: trend)
            if let note = dayEntry?.note {
                // Italic and grey, as a meal's note reads in the table below.
                MarkdownText.inline(note, hidingTagHashes: true)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .liensDeNote()
                    .dayEntryActions(edit: onEditDay, delete: onDeleteDay)
            }
            if !windowed.isEmpty {
                chart(windowed, trend: trend)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    /// Three words rather than a segmented control: the window is a
    /// setting, and the accent-filled segment was the loudest thing on screen.
    private var periodPicker: some View {
        HStack(spacing: 10) {
            ForEach(NutritionWeightPeriod.allCases) { option in
                Button(option.displayName) { period = option }
                    .buttonStyle(.plain)
                    .font(.caption.weight(option == period ? .semibold : .regular))
                    .foregroundStyle(option == period ? .primary : .secondary)
            }
        }
    }

    private func chart(_ windowed: [WeightPoint], trend: [WeightPoint]) -> some View {
        let hovered = hoveredDate.flatMap { nearest(to: $0, in: windowed) }
        let shown = windowed.first { $0.dateKey == day }
        return Chart {
            // The weigh-ins themselves, faint: the trend is what is read.
            ForEach(windowed, id: \.dateKey.raw) { point in
                PointMark(
                    x: .value("Date", point.dateKey.date()),
                    y: .value("Poids", point.weightKg)
                )
                .symbolSize(8)
                .foregroundStyle(Color.accentColor.opacity(0.3))
            }
            ForEach(trend, id: \.dateKey.raw) { point in
                LineMark(
                    x: .value("Date", point.dateKey.date()),
                    y: .value("Tendance", point.weightKg)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            // The day on screen, so the line below it has a place on the curve.
            if let shown {
                PointMark(
                    x: .value("Date", shown.dateKey.date()),
                    y: .value("Poids", shown.weightKg)
                )
                .symbolSize(24)
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered.dateKey.date()))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top, spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        bubble(hovered)
                    }
            }
        }
        .chartYScale(domain: yDomain(windowed))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartXSelection(value: $hoveredDate)
        // Beside the hover selection rather than over it: an overlay would
        // take the pointer from the chart, and the hover with it.
        .simultaneousGesture(TapGesture().onEnded {
            if let hovered { onSelectDay(hovered.dateKey) }
        })
        .frame(height: 120)
    }

    private func bubble(_ point: WeightPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.dateOnly(point.dateKey.date()))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Format.typedNumber(point.weightKg)) kg")
                .font(.caption.monospacedDigit())
            if let note = point.note {
                MarkdownText.inline(note, hidingTagHashes: true)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }

    /// The weigh-in closest to the pointer: weigh-ins are days apart, and the
    /// pointer is almost never exactly on one.
    private func nearest(to date: Date, in windowed: [WeightPoint]) -> WeightPoint? {
        windowed.min {
            abs($0.dateKey.date().timeIntervalSince(date))
                < abs($1.dateKey.date().timeIntervalSince(date))
        }
    }

    /// Fitted, never from zero: a 2 kg trend drawn from zero is a flat line.
    private func yDomain(_ windowed: [WeightPoint]) -> ClosedRange<Double> {
        let values = windowed.map(\.weightKg)
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        return (low - 0.5)...(high + 0.5)
    }

    // MARK: - The day's weigh-in

    /// The weigh-in of the day on screen, large; without one, the last known
    /// weight in grey with its date, and the way to add the day's.
    @ViewBuilder
    private func figureRow(trend: [WeightPoint]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let entry = dayEntry {
                Text("\(Format.typedNumber(entry.weightKg)) kg")
                    .font(.title3.monospacedDigit())
                    .dayEntryActions(edit: onEditDay, delete: onDeleteDay)
            } else if let last = points.last {
                Text("\(Format.typedNumber(last.weightKg)) kg")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("le \(last.dateKey.date().formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Aucune pesée")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            // On the trend, not the raw ends: two weigh-ins a morning apart
            // can differ by a kilo of water.
            if let first = trend.first, let end = trend.last, trend.count > 1 {
                Text(Format.signedTwoDecimals(end.weightKg - first.weightKg)
                     + " kg sur \(period.displayName)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Écart de la moyenne sur 7 jours")
            }
            if dayEntry == nil {
                Button(action: onEditDay) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Ajouter la pesée du jour")
            }
        }
    }
}

private extension View {
    /// Double-click to edit, right click for the menu — the gestures of a
    /// food row, said once in the tooltip.
    func dayEntryActions(
        edit: @escaping () -> Void, delete: @escaping () -> Void
    ) -> some View {
        contentShape(.rect)
            .onTapGesture(count: 2, perform: edit)
            .help("Double-cliquez pour modifier, clic droit pour supprimer")
            .contextMenu {
                Button("Modifier…", action: edit)
                Divider()
                Button("Supprimer", role: .destructive, action: delete)
            }
    }
}
