// Cairn/Features/Nutrition/MacroGauge.swift
import SwiftUI

/// One "consumed / target" figure with a thin progress bar — the unit of
/// the day's summary row. System colours only; the overshoot is graduated
/// like suivinut's: orange while it's still close, red once frankly blown.
struct MacroGauge: View {
    let title: String
    let consumed: Double
    let target: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(figure).font(.title3.monospacedDigit())
            if let target, target > 0 {
                ProgressView(value: min(consumed / target, 1))
                    .tint(overshootColor(target: target) ?? .accentColor)
                // suivinut's « reste » line: the number the next meal is
                // actually planned against, not just a bar to squint at.
                Text(remainingLabel(target: target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(overshootColor(target: target)
                                     .map(AnyShapeStyle.init)
                                     ?? AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overshootColor(target: Double) -> Color? {
        switch NutritionMath.overshoot(consumed: consumed, target: target) {
        case nil: nil
        case .moderate: .orange
        case .heavy: .red
        }
    }

    /// Derived from the rounded figures the gauge itself shows: computed on
    /// the raw values, it announced "dépassé de 1 g" under a "33 / 33 g" that
    /// exceeds nothing the reader can see.
    private func remainingLabel(target: Double) -> String {
        let remaining = target.rounded() - consumed.rounded()
        return remaining >= 0
            ? "reste \(rounded(remaining)) \(unit)"
            : "dépassé de \(rounded(-remaining)) \(unit)"
    }

    private var figure: String {
        guard let target else { return "\(rounded(consumed)) \(unit)" }
        return "\(rounded(consumed)) / \(rounded(target)) \(unit)"
    }

    private func rounded(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}
