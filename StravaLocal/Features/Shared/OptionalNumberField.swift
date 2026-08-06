import SwiftUI

/// A numeric filter field that stays empty when unset, rather than showing a
/// misleading 0, and accepts a comma as decimal separator.
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
                    value = new.isEmpty
                        ? nil
                        : Double(new.replacingOccurrences(of: ",", with: "."))
                }
            Text(unit)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .onChange(of: value) { _, new in
            // Keeps the field in step when the filter is reset from elsewhere.
            if new == nil, !text.isEmpty { text = "" }
        }
    }
}
