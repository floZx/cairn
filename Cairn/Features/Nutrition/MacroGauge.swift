// Cairn/Features/Nutrition/MacroGauge.swift
import SwiftUI

/// One "consumed / target" figure with a thin progress bar — the unit of
/// the day's summary row. System colours only; red is reserved for an
/// exceeded target, which is the one state that must jump out.
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
                    .tint(consumed > target ? .red : .accentColor)
                // suivinut's « reste » line: the number the next meal is
                // actually planned against, not just a bar to squint at.
                Text(remainingLabel(target: target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(consumed > target ? .red : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func remainingLabel(target: Double) -> String {
        let remaining = target - consumed
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
