import SwiftUI

/// A field for a number someone types, comma or point.
///
/// Not `TextField(value:format:)`, which reformats on every keystroke: the
/// moment the separator is typed, the value parses as the whole part alone,
/// the field is rewritten from it, and the separator disappears — "71,05"
/// could not be entered at all. Reported on the weigh-in sheet, 13 August
/// 2026, and true of every decimal field in the application.
///
/// The text lives here and the value follows it, exactly as
/// `OptionalNumberField` — written first for the sidebar filters — already
/// does. This is its non-optional twin: a weight, a quantity and a daily
/// target always have a value, and an empty field would mean zero rather than
/// "unset".
struct DecimalField: View {
    let placeholder: String
    @Binding var value: Double
    /// Nil lets the field take what the layout gives it.
    var width: CGFloat?
    /// Passed in rather than owned: a sheet decides which field the keyboard
    /// lands in, and `focused` only binds the view it is written on.
    var focus: FocusState<Bool>.Binding?

    @State private var text = ""

    var body: some View {
        field
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, new in
                // An empty field, or one holding just a separator, is a number
                // being typed — not a zero. Leaving the value alone until it
                // parses is what lets someone clear a field and retype it.
                if let parsed = Self.parse(new) { value = parsed }
            }
            .onChange(of: value) { _, new in
                // Only when the text does not already mean this value:
                // rewriting it unconditionally would collapse "71," back to
                // "71" before the decimals were reached.
                guard Self.parse(text) != new else { return }
                text = Self.format(new)
            }
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField(placeholder, text: $text).focused(focus)
        } else {
            TextField(placeholder, text: $text)
        }
    }

    /// Both separators, because both are typed: the keypad gives a point and
    /// the French keyboard a comma, and a journal is not the place to teach
    /// anyone the difference.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// The value as someone would have typed it: no trailing ",0" on a round
    /// figure, and a comma rather than a point.
    static func format(_ value: Double) -> String {
        guard value != value.rounded() else { return String(Int(value)) }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }
}
