// Cairn/Features/Nutrition/NutritionWeightCard.swift
import SwiftUI
import Charts

/// The window of the weight chart on the nutrition screen. Its own key, apart
/// from `WeightPeriod`: the weight screen offers other lengths.
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

/// The weight trend beside the calorie gauge: the latest weigh-in, how far it
/// moved over the window, and the line. Read-only — the weigh-ins come from
/// Garmin.
struct NutritionWeightCard: View {
    /// Ascending by date.
    let points: [WeightPoint]

    @AppStorage(NutritionWeightPeriod.storageKey)
    private var period: NutritionWeightPeriod = .threeMonths

    var body: some View {
        // Anchored on the last weigh-in, as on the weight screen: a scale left
        // unused for a month still shows a line, not an empty frame.
        let windowed = WeightStats.window(points, days: period.days)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Poids").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Période", selection: $period) {
                    ForEach(NutritionWeightPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            if let last = windowed.last {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Format.typedNumber(last.weightKg)) kg")
                        .font(.title3.monospacedDigit())
                    if let first = windowed.first, windowed.count > 1 {
                        Text(Format.signedTwoDecimals(last.weightKg - first.weightKg)
                             + " kg sur \(period.displayName)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            chart(windowed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chart(_ windowed: [WeightPoint]) -> some View {
        Chart(windowed, id: \.dateKey.raw) { point in
            LineMark(
                x: .value("Date", point.dateKey.date()),
                y: .value("Poids", point.weightKg)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
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
        .frame(height: 90)
    }

    /// Fitted, never from zero: a 2 kg trend drawn from zero is a flat line.
    private func yDomain(_ windowed: [WeightPoint]) -> ClosedRange<Double> {
        let values = windowed.map(\.weightKg)
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        return (low - 0.5)...(high + 0.5)
    }
}
