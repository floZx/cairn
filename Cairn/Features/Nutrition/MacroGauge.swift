// Cairn/Features/Nutrition/MacroGauge.swift
import SwiftUI

/// One "consumed / target" figure with a thin progress bar — the unit of
/// the day's summary row. System colours only, and the same four states a
/// meal's line carries: grey while the day is still being built, green once
/// the target is within a tenth, orange while it is still close above it,
/// red once frankly blown.
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
                    // Grey rather than the accent while there is nothing to
                    // say: green, orange and red keep the colour to themselves,
                    // as on a meal's totals.
                    .tint(gaugeColor(target: target) ?? .secondary)
                // suivinut's « reste » line: the number the next meal is
                // actually planned against, not just a bar to squint at.
                Text(remainingLabel(target: target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(gaugeColor(target: target)
                                     .map(AnyShapeStyle.init)
                                     ?? AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nil means "nothing to say yet": the bar keeps the accent colour and the
    /// line under it stays grey.
    ///
    /// The overshoot answers first, as it does on a meal's line — a figure
    /// past its target is past it, whatever else it is, and the warning
    /// outranks the encouragement.
    private func gaugeColor(target: Double) -> Color? {
        Self.color(consumed: consumed, target: target)
    }

    static func color(consumed: Double, target: Double) -> Color? {
        switch NutritionMath.overshoot(consumed: consumed, target: target) {
        case .moderate: .orange
        case .heavy: .red
        case nil:
            NutritionMath.isOnTarget(consumed: consumed, target: target)
                ? .green : nil
        }
    }

    /// Derived from the rounded figures the gauge itself shows: computed on
    /// the raw values, it announced "dépassé de 1 g" under a "33 / 33 g" that
    /// exceeds nothing the reader can see.
    private func remainingLabel(target: Double) -> String {
        Self.remainingLabel(consumed: consumed, target: target, unit: unit)
    }

    static func remainingLabel(consumed: Double, target: Double, unit: String) -> String {
        func rounded(_ value: Double) -> String { "\(Int(value.rounded()))" }
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
