import SwiftUI

/// A numeric field that stays empty when unset, rather than showing a misleading
/// 0, and accepts a comma as decimal separator.
///
/// It was written for the sidebar filters, which always start empty, and its text
/// began life as an empty string whatever value it was handed. Reused in the
/// activity editor it showed a blank distance beside a real one — which reads as
/// data lost, though nothing was. Hence the two-way sync below.
struct OptionalNumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 8)
            TextField("", text: $text)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, new in
                    value = Self.parse(new)
                }
            Text(unit)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { _, new in
            // Only when the text does not already mean this value. Reformatting
            // unconditionally would rewrite what the user is typing: "12," would
            // collapse back to "12" before they reached the decimals.
            guard Self.parse(text) != new else { return }
            text = Self.format(new)
        }
    }

    static func parse(_ text: String) -> Double? {
        text.isEmpty
            ? nil
            : Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// The value as someone would have typed it: no trailing ",0" on a round
    /// figure, and a comma rather than a point.
    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        guard value != value.rounded() else { return String(Int(value)) }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }
}
