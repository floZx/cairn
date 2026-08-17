import Foundation

/// What the recovery has to say to the reader, once, in French.
///
/// Pulled out of the view because the sentence is decided by what the
/// recovery found and not by anything on screen, and a view cannot be asked
/// that question in a test; this can.
///
/// It used to hold a second half — a banner for a note changed or deleted
/// under an unsaved edit, back when the journal was a folder shared with
/// Obsidian and something had to arbitrate between a sentence typed here and
/// one typed on the phone. That arbitration went with the second writer: a
/// `context.save()` does not race anyone. So did the half before it, for a
/// write that failed: a `context.save()` fails the way a full disk does, not
/// the way an unplugged one did. Both are gone rather than kept against the
/// day the base gains a second writer — a slice whose whole thesis is
/// removal is no place to keep code for a caller nobody has asked for.
struct JournalNotice: Equatable {
    /// The sentence itself, in French. Not optional: both factories below
    /// always produce one, and a notice with nothing to say is expressed by
    /// the absence of a notice — see `notice(unreadable:)`.
    let message: String

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
