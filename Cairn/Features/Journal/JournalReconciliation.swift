import Foundation

/// What to do when the note being edited changed on disk.
///
/// Pulled out as a value because it is the one decision in the whole feature
/// where being wrong loses work — either a sentence typed here, or one typed on
/// the phone. Everything around it is plumbing; this is the rule.
enum JournalReconciliation {
    enum Outcome: Equatable {
        /// Take what the disk says.
        case adopt
        /// The file changed under an unsaved edit: keep the buffer, warn.
        case conflict
        /// The file went away under an unsaved edit: keep the buffer, warn.
        case vanished
    }

    /// Whether the file is still exactly as we last left it — either what was
    /// read from it when the note was opened, or what we last wrote into it.
    ///
    /// Asked before `outcome(isDirty:bufferText:diskText:)`, because the
    /// watcher fires for every change anywhere in the folder, our own saves
    /// included, and each one re-reads the whole folder. Without this the note
    /// being typed into would be reconciled against a file nobody has touched,
    /// and the banner would rise on an ordinary pause in the typing — the save
    /// fires, its own event comes back, and by then another word has been
    /// written — or on some unrelated note arriving from iCloud.
    ///
    /// No file and an empty file are the same state: a note emptied to nothing
    /// is removed from the folder, so both mean a day with nothing written.
    static func isUnchanged(diskText: String?, baselineText: String) -> Bool {
        (diskText ?? "") == baselineText
    }

    static func outcome(
        isDirty: Bool, bufferText: String, diskText: String?
    ) -> Outcome {
        // Nothing unsaved: whatever the disk holds is more recent than what is
        // merely being displayed.
        guard isDirty else { return .adopt }
        guard let diskText else { return .vanished }
        // The common case by far: our own debounced save coming back through
        // the watcher. Treating it as a conflict would raise a banner after
        // every pause in typing.
        return diskText == bufferText ? .adopt : .conflict
    }
}
