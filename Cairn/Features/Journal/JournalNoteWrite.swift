import Foundation
import SwiftData

/// The one rule for putting a text into a day's note.
///
/// Lifted out of `JournalStore.saveNow()` when `cairn-note` arrived: the
/// terminal writes the same notes the pane does, and a second copy of "empty
/// means gone" is a copy that drifts. The store keeps the typing, the
/// debounce and the list around it; what is left here is only the decision.
///
/// Takes a `ModelContext` rather than living on the store: the tool has no
/// store, and this rule never needed one.
enum JournalNoteWrite {
    /// What the write turned out to be, for a caller that has something to
    /// say about it. `JournalStore` ignores it; the tool prints it.
    enum Outcome {
        /// A day that had no note has one now.
        case created
        /// A note that existed was rewritten.
        case updated
        /// A note emptied to nothing, and taken out with it.
        case deleted
        /// Nothing was there, and nothing was typed: no row is made.
        case nothing
    }

    /// The row for that day, or nil. The one fetch, so the predicate is
    /// written once.
    static func row(for date: DateKey, in context: ModelContext) -> JournalNote? {
        let raw = date.raw
        var descriptor = FetchDescriptor<JournalNote>(
            predicate: #Predicate { $0.dateKeyRaw == raw }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Poses `text` as that day's note. Does not save: the caller decides
    /// when, and `JournalStore` has a debounce that depends on deciding it.
    @discardableResult
    static func apply(
        _ text: String, for date: DateKey, in context: ModelContext
    ) -> Outcome {
        if let existing = row(for: date, in: context) {
            existing.setText(text)
            // A note emptied to nothing goes, exactly as an emptied file used
            // to leave the vault: opening today's note and typing nothing must
            // not leave a blank day in the journal. The rule is
            // `JournalNote.isEmpty`, and it has not changed.
            //
            // The row goes; the note does not, when this is the pane calling.
            // That is a pause in the middle of writing — select-all, delete,
            // think — and `JournalStore.refresh()` puts the open day's row
            // back on its own.
            if existing.isEmpty {
                context.delete(existing)
                return .deleted
            }
            return .updated
        }
        let note = JournalNote(dateKey: date, text: text)
        // Never inserted at all when there is nothing to keep.
        guard !note.isEmpty else { return .nothing }
        context.insert(note)
        return .created
    }
}
