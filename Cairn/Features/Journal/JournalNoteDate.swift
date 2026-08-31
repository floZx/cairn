import Foundation

/// The day `cairn-note` was asked for, read off its one argument.
///
/// Kept beside the journal rather than inside the tool so the suite can reach
/// it: `CairnTests` links the application, not the executable.
///
/// Three spellings and no more, each unambiguous on sight:
///
/// - nothing at all — today;
/// - `2026-08-14` or `20260814` — that day, the dashes optional because a
///   date typed in a hurry rarely keeps them;
/// - `-1`, `+3` — days from today, the sign always written. A bare `1` is
///   refused on purpose: it reads as a day of the month as easily as as an
///   offset, and guessing which would be wrong half the time.
enum JournalNoteDate {
    /// The day asked for, or nil when the argument is not one of the three.
    ///
    /// `today` is a parameter with no default reaching for the clock inside:
    /// a test that could not name the day would have to be written against
    /// whatever day it runs on.
    static func parse(_ argument: String?, today: DateKey) -> DateKey? {
        let raw = (argument ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return today }

        if raw.first == "-" || raw.first == "+" {
            let digits = raw.dropFirst()
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber),
                  let offset = Int(raw)
            else { return nil }
            return today.advanced(by: offset)
        }

        // `DateKey(raw:)` is the whole validation of the dashed form — it
        // already refuses anything that is not exactly `AAAA-MM-JJ`, month and
        // day included — so the compact form is turned into it rather than
        // validated a second way that could disagree.
        if raw.count == 8, raw.allSatisfy(\.isNumber) {
            let year = raw.prefix(4)
            let month = raw.dropFirst(4).prefix(2)
            let day = raw.suffix(2)
            return DateKey(raw: "\(year)-\(month)-\(day)")
        }

        return DateKey(raw: raw)
    }
}
