import Testing
import Foundation
@testable import Cairn

/// The one argument `cairn-note` takes. Driven against a named day rather
/// than the clock, which is why `parse` has no default for `today`.
@Suite("JournalNoteDate")
struct JournalNoteDateTests {
    private let today = DateKey(raw: "2026-08-31")!

    @Test("Nothing at all is today")
    func empty() {
        #expect(JournalNoteDate.parse(nil, today: today) == today)
        #expect(JournalNoteDate.parse("", today: today) == today)
        #expect(JournalNoteDate.parse("   ", today: today) == today)
    }

    @Test("The dashed form is the day itself")
    func dashed() {
        #expect(JournalNoteDate.parse("2026-08-14", today: today)?.raw == "2026-08-14")
    }

    @Test("The compact form says the same day")
    func compact() {
        #expect(JournalNoteDate.parse("20260814", today: today)?.raw == "2026-08-14")
    }

    /// The compact form goes through `DateKey(raw:)` rather than being
    /// validated a second way, so it accepts and refuses exactly what the
    /// dashed one does — a thirteenth month refused, and a 30 February
    /// accepted, since `DateKey` checks bounds rather than the calendar.
    /// Stated here rather than left implicit: the two spellings agreeing is
    /// the whole point of turning one into the other.
    @Test("The compact form is refused exactly where the dashed one is")
    func compactInvalid() {
        #expect(JournalNoteDate.parse("20261301", today: today) == nil)
        #expect(JournalNoteDate.parse("20260001", today: today) == nil)
        #expect(JournalNoteDate.parse("20260832", today: today) == nil)
        #expect(
            JournalNoteDate.parse("20260230", today: today)
                == JournalNoteDate.parse("2026-02-30", today: today)
        )
    }

    @Test("A signed number counts days from today")
    func offsets() {
        #expect(JournalNoteDate.parse("-1", today: today)?.raw == "2026-08-30")
        #expect(JournalNoteDate.parse("-7", today: today)?.raw == "2026-08-24")
        #expect(JournalNoteDate.parse("+3", today: today)?.raw == "2026-09-03")
    }

    /// The month rolls over on its own: the offset goes through
    /// `DateKey.advanced(by:)`, which is the calendar's answer, not
    /// arithmetic on the raw string.
    @Test("An offset crosses the start of the month")
    func offsetAcrossMonth() {
        let first = DateKey(raw: "2026-09-01")!
        #expect(JournalNoteDate.parse("-1", today: first)?.raw == "2026-08-31")
    }

    /// A bare number is ambiguous — a day of the month reads exactly like an
    /// offset — so it is refused rather than guessed at.
    @Test("A number without a sign is not a day")
    func unsignedNumber() {
        #expect(JournalNoteDate.parse("1", today: today) == nil)
        #expect(JournalNoteDate.parse("14", today: today) == nil)
    }

    @Test("Anything else is refused")
    func rubbish() {
        #expect(JournalNoteDate.parse("hier", today: today) == nil)
        #expect(JournalNoteDate.parse("2026-8-14", today: today) == nil)
        #expect(JournalNoteDate.parse("-", today: today) == nil)
        #expect(JournalNoteDate.parse("-x", today: today) == nil)
    }
}
