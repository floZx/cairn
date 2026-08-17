import Foundation

/// What the editor has to say above the text, and what the reader may do
/// about it.
///
/// Pulled out of the view because a conflict decides both the wording and
/// which buttons appear, and getting that mapping wrong is not cosmetic: a
/// **Recharger** shown over the wrong note drops a buffer that was never in
/// conflict. A view cannot be asked that question in a test; this can.
///
/// `Conflict` has had no caller in the journal since the notes left the
/// shared folder: a `context.save()` does not race a second writer the way a
/// file on disk did. It stays regardless, still held to the letter by
/// `Tests/JournalNoticeTests.swift`, because nothing here says the base can
/// never gain a second writer again.
///
/// What this struct's other half used to hold — a write that failed, `.here`
/// on the note itself or `.elsewhere` on the one just left — went with the
/// folder entirely: a `context.save()` fails the way a full disk does, not
/// the way an unplugged one did, and the recovery never produces that shape.
/// In its place: `notice(unreadable:)`, the recovery's own report, wired
/// from `StoreMaintenance.run` — the one call site this struct has in
/// production today.
struct JournalNotice: Equatable {
    /// What used to be decided when the note being edited changed on disk.
    ///
    /// Lived in `JournalReconciliation` while the folder was shared with
    /// Obsidian and something had to arbitrate between a sentence typed here
    /// and one typed on the phone. That arbitration has gone with the second
    /// writer; the vocabulary stays here, where the only remaining reader of
    /// it is, rather than in a file whose one rule no longer applies.
    enum Outcome: Equatable {
        /// Take what the other copy says.
        case adopt
        /// It changed under an unsaved edit: keep the buffer, warn.
        case conflict
        /// It went away under an unsaved edit: keep the buffer, warn.
        case vanished
    }

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

    var conflict: Conflict?
    /// The recovery's own report, in French — what `notice(unreadable:)`
    /// produces. Never set alongside `conflict`: the recovery runs once, at
    /// launch, before an editing session exists for anything to conflict
    /// with.
    var message: String?

    /// The notice for a note on screen, or nil when there is nothing to say.
    ///
    /// - Parameter conflict: what happened to the note being edited — not
    ///   necessarily the one displayed.
    static func notice(conflict: Outcome?) -> JournalNotice? {
        let banner: Conflict? = switch conflict {
        case .conflict: .changedElsewhere
        case .vanished: .deletedElsewhere
        // `.adopt` is the silent case and never reaches the store's
        // property, but a notice for it would be a lie either way.
        case .adopt, nil: nil
        }
        guard let banner else { return nil }
        return JournalNotice(conflict: banner)
    }

    /// The recovery's own report: which files it took in imperfectly — a
    /// note whose bytes were not valid UTF-8, either kind reread and, rarer,
    /// unreadable outright (`JournalImport.Outcome.unreadable`). Every one of
    /// them is still in the store; this is only the trace that they deserve
    /// a second look, and it is the only trace the reader gets — a file
    /// imported imperfectly and said nothing about is a file nobody knows to
    /// check.
    ///
    /// `nil` for an empty list rather than an empty message: called once, at
    /// the recovery, whether or not it found anything to report.
    static func notice(unreadable: [String]) -> JournalNotice? {
        guard !unreadable.isEmpty else { return nil }
        let subject = unreadable.count == 1 ? "fichier" : "fichiers"
        let names = unreadable.joined(separator: ", ")
        return JournalNotice(
            message: """
                La reprise n'a pas pu lire \(unreadable.count) \(subject) comme \
                prévu ; repris quand même, à vérifier : \(names).
                """
        )
    }

    /// The recovery could not run at all: the folder it was to read is
    /// unreadable — a stale path, an unmounted volume, a vault reorganised
    /// since. Nothing was imported and nothing was lost; the next launch
    /// tries again, because the marker is only set by a run that succeeded.
    ///
    /// Names the folder, which is the whole point of the sentence: the folder
    /// picker went away with the folder itself, so the path recorded at the
    /// time is the only thing that tells the reader *which* place to put back
    /// within reach.
    ///
    /// Never nil, unlike `notice(unreadable:)`: this is only called when a
    /// failure has already happened, and a failure with nothing to say would
    /// be the silence this exists to break.
    static func notice(recoveryFailure folder: String?) -> JournalNotice {
        guard let folder, !folder.isEmpty else {
            return JournalNotice(
                message: """
                    La reprise du journal a échoué ; elle sera retentée au \
                    prochain lancement.
                    """
            )
        }
        return JournalNotice(
            message: """
                La reprise du journal n'a pas pu lire le dossier « \(folder) » ; \
                elle sera retentée au prochain lancement, et vos notes y \
                restent intactes.
                """
        )
    }
}
