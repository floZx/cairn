import Foundation

/// Which note of the journal is being written in, if any.
///
/// Lifted out of `JournalDetailView` for the same reason as `JournalNotice`:
/// two events can arrive together — the note on screen changes, the editor is
/// asked for — and what they add up to is a small state machine. One that only
/// a view holds is one that only reading can check, and reading is what missed
/// it twice.
///
/// The rule that makes it order-proof: entering records *which* note, and
/// leaving clears only when the note being left is the one recorded. ⌘N changes
/// the note and asks for the editor in the same breath, and SwiftUI promises no
/// order between the two `onChange` handlers that carry them; whichever runs
/// first, the request survives and the note left behind goes back to reading.
struct JournalEditing: Equatable, Sendable {
    /// The note being written in. Nil is reading, and that is where one starts.
    private(set) var note: DateKey?

    func isEditing(_ id: DateKey) -> Bool { note == id }

    /// A click in the pane, or `e`, `n`, `⏎` from the list, or ⌘N.
    mutating func requested(for id: DateKey) { note = id }

    /// Another note is on screen now. The one just left goes back to reading —
    /// unless the recorded note is no longer it, which means the request for
    /// the editor got here first and named the note that has just arrived.
    mutating func left(_ previous: DateKey) {
        guard note == previous else { return }
        note = nil
    }

    /// Escape: writing is over, whichever note it was.
    mutating func ended() { note = nil }
}
