import SwiftUI

struct FilterBar: View {
    @Binding var filter: ActivityFilter

    var body: some View {
        HStack(spacing: 12) {
            Picker("Période", selection: $filter.period) {
                ForEach(DatePeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .fixedSize()

            OptionalNumberField(
                title: "Distance min.", unit: "km", value: $filter.minDistanceKm
            )
            OptionalNumberField(
                title: "Distance max.", unit: "km", value: $filter.maxDistanceKm
            )
            OptionalNumberField(
                title: "Durée min.", unit: "min", value: $filter.minDurationMinutes
            )
            OptionalNumberField(
                title: "D+ min.", unit: "m", value: $filter.minElevation
            )

            Spacer()

            if filter.region != nil {
                Button {
                    filter.region = nil
                } label: {
                    Label("Zone de la carte", systemImage: "xmark.circle.fill")
                }
                .help("Retirer le filtre géographique")
            }

            if filter.isActive {
                Button("Réinitialiser") { filter = .none }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// A numeric field that stays empty when the filter isn't set, rather than
/// showing a misleading 0.
private struct OptionalNumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $text)
                .frame(width: 72)
                .onChange(of: text) { _, new in
                    value = new.isEmpty
                        ? nil
                        : Double(new.replacingOccurrences(of: ",", with: "."))
                }
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
        .onChange(of: value) { _, new in
            if new == nil, !text.isEmpty { text = "" }
        }
    }
}
