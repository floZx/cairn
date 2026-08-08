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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var figure: String {
        guard let target else { return "\(rounded(consumed)) \(unit)" }
        return "\(rounded(consumed)) / \(rounded(target)) \(unit)"
    }

    private func rounded(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}
