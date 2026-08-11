import Foundation

/// What the editor has to say above the text, and what the reader may do
/// about it.
///
/// Pulled out of the view because three pieces of state — a conflict, a save
/// that failed, and which note it failed on — decide both the wording and
/// which buttons appear, and getting that mapping wrong is not cosmetic: a
/// **Recharger** shown over the wrong note drops a buffer that was never in
/// conflict. A view cannot be asked that question in a test; this can.
struct JournalNotice: Equatable {
    /// The note moved under an unsaved edit.
    ///
    /// What is on screen is the typing, never the file — losing a sentence to
    /// a sync is the one failure this whole mechanism exists to prevent. The
    /// banner offers the choice; it never takes it.
    enum Conflict: Equatable {
        case changedElsewhere
        case deletedElsewhere

        var message: String {
            switch self {
            case .changedElsewhere:
                "La note a été modifiée ailleurs. Votre texte est conservé ici."
            case .deletedElsewhere:
                "Le fichier a été supprimé ailleurs. Votre texte est conservé ici."
            }
        }

        /// What an unanswered banner costs, which the message never says.
        ///
        /// Nothing writes while the banner is up — that is what stops the
        /// debounce, or quitting, from answering for the reader — so the text
        /// held here lives in memory only, and quitting drops it. Saying so is
        /// the price of not resolving the question silently: the alternative
        /// was to keep writing the buffer over a file the reader had just been
        /// warned about, which is what the banner exists to prevent.
        var consequence: String {
            let end = switch self {
            case .changedElsewhere: "garderait la version du fichier"
            case .deletedElsewhere: "laisserait la note supprimée"
            }
            return """
                Il n'est pas enregistré tant que vous n'avez pas choisi : \
                quitter Cairn \(end).
                """
        }

        /// There is nothing to reload from a file that is gone.
        var offersReload: Bool { self == .changedElsewhere }
    }

    /// A save that did not go through, and where.
    ///
    /// The distinction is the whole point: the two cases block different
    /// things, and telling the reader the wrong one is worse than saying
    /// nothing — it would have them keep typing into a note that is dropping
    /// every keystroke.
    enum Failure: Equatable {
        /// On the note on screen. Typing still reaches it and each pause tries
        /// the save again; what is blocked is leaving for another note.
        case here(String)
        /// On another note, which the journal has not been able to let go of.
        /// Everything typed here is refused until that one is written.
        case elsewhere(String, DateKey)

        /// The system's own words about the failure.
        var message: String {
            switch self {
            case let .here(message), let .elsewhere(message, _): message
            }
        }

        /// What it means for the person at the keyboard, which is the part the
        /// system message never says.
        var consequence: String {
            switch self {
            case .here:
                """
                Le journal ne peut pas changer de note tant que ce texte n'est \
                pas enregistré.
                """
            case let .elsewhere(_, date):
                """
                Ce que vous écrivez ici n'est pas conservé tant que la note du \
                \(Format.fullDate(date.date())) n'est pas enregistrée.
                """
            }
        }
    }

    var conflict: Conflict?
    var failure: Failure?

    /// The notice for a note on screen, or nil when there is nothing to say.
    ///
    /// - Parameters:
    ///   - conflict: `JournalStore.conflict`, which belongs to the note being
    ///     edited — not necessarily the one displayed.
    ///   - writeFailure: `JournalStore.writeFailure`.
    ///   - failingDate: `JournalStore.pendingWriteFailure`.
    ///   - displayedDate: the note the editor is showing.
    static func notice(
        conflict: JournalReconciliation.Outcome?,
        writeFailure: String?,
        failingDate: DateKey?,
        displayedDate: DateKey
    ) -> JournalNotice? {
        let failure: Failure? = writeFailure.map { message in
            // No date at all is read as the note on screen: the store keeps
            // the two in lockstep, and of the two readings this is the one
            // that cannot send the reader to a day that is not stuck.
            guard let failingDate, failingDate != displayedDate else {
                return .here(message)
            }
            return .elsewhere(message, failingDate)
        }

        // A failure on another note places the conflict on that note too — the
        // store only ever raises one for the note it is editing, which is the
        // one it could not write. Its buttons would then act on a note nobody
        // can see, and `reloadConflicted()` discards the buffer, the edited
        // date and the baseline unconditionally: pressing **Recharger** here
        // would throw away the very text that failed to save, on a note the
        // reader was not even looking at.
        let banner: Conflict?
        if case .elsewhere = failure {
            banner = nil
        } else {
            banner = switch conflict {
            case .conflict: .changedElsewhere
            case .vanished: .deletedElsewhere
            // `.adopt` is the silent case and never reaches the store's
            // property, but a notice for it would be a lie either way.
            case .adopt, nil: nil
            }
        }

        guard banner != nil || failure != nil else { return nil }
        return JournalNotice(conflict: banner, failure: failure)
    }
}
