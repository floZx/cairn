import Testing
import Foundation
@testable import Cairn

/// The mapping from the store's state to what the editor's header says, and to
/// which buttons it offers. Held to the letter here because the view cannot be
/// asked: a **Recharger** shown over the wrong note discards a buffer.
@Suite("JournalNotice")
struct JournalNoticeTests {
    private let displayed = DateKey(raw: "2026-08-11")!
    private let other = DateKey(raw: "2026-08-10")!

    @Test("rien à signaler ne pose aucun bandeau")
    func nothingWrongSaysNothing() {
        #expect(
            JournalNotice.notice(
                conflict: nil, writeFailure: nil, failingDate: nil,
                displayedDate: displayed
            ) == nil
        )
    }

    @Test("une note modifiée ailleurs propose de recharger")
    func aChangedNoteOffersToReload() throws {
        let notice = try #require(
            JournalNotice.notice(
                conflict: .conflict, writeFailure: nil, failingDate: nil,
                displayedDate: displayed
            )
        )
        #expect(notice.conflict == .changedElsewhere)
        #expect(notice.failure == nil)
        #expect(notice.conflict?.offersReload == true)
        #expect(
            notice.conflict?.message
                == "La note a été modifiée ailleurs. Votre texte est conservé ici."
        )
    }

    @Test("un fichier supprimé ailleurs ne propose rien à recharger")
    func aDeletedFileHasNothingToReload() throws {
        let notice = try #require(
            JournalNotice.notice(
                conflict: .vanished, writeFailure: nil, failingDate: nil,
                displayedDate: displayed
            )
        )
        #expect(notice.conflict == .deletedElsewhere)
        #expect(notice.conflict?.offersReload == false)
        #expect(
            notice.conflict?.message
                == "Le fichier a été supprimé ailleurs. Votre texte est conservé ici."
        )
    }

    /// Nothing is written while the banner is up — that is what keeps the
    /// debounce from answering the question for the reader — so the text held
    /// there lives in memory only. The banner has to say what that costs, and
    /// the two cases do not cost the same thing.
    @Test("le bandeau dit ce que coûte une question sans réponse")
    func theBannerSaysWhatLeavingItUnansweredCosts() {
        #expect(
            JournalNotice.Conflict.changedElsewhere.consequence.contains(
                "quitter Cairn garderait la version du fichier"
            )
        )
        #expect(
            JournalNotice.Conflict.deletedElsewhere.consequence.contains(
                "quitter Cairn laisserait la note supprimée"
            )
        )
    }

    /// `.adopt` is the silent case: the store never publishes it, and a notice
    /// for it would say a change was pending when it has already been taken.
    @Test("une reprise silencieuse ne dit rien")
    func adoptingIsSilent() {
        #expect(
            JournalNotice.notice(
                conflict: .adopt, writeFailure: nil, failingDate: nil,
                displayedDate: displayed
            ) == nil
        )
    }

    @Test("un échec sur la note affichée annonce le blocage du changement de note")
    func aFailureHereBlocksLeaving() throws {
        let notice = try #require(
            JournalNotice.notice(
                conflict: nil, writeFailure: "La note n'a pas pu être enregistrée.",
                failingDate: displayed, displayedDate: displayed
            )
        )
        #expect(notice.conflict == nil)
        #expect(notice.failure == .here("La note n'a pas pu être enregistrée."))
        #expect(
            notice.failure?.consequence
                == "Le journal ne peut pas changer de note tant que ce texte n'est pas enregistré."
        )
    }

    /// The case the widened gate exists for: the save failed on the way out of
    /// a note, so the store stayed there while the screen moved on. What is
    /// typed here is refused outright, and the day that is stuck has to be
    /// named — "ce texte" would point at text the reader cannot see.
    @Test("un échec sur une autre note dit que la frappe ici n'est pas conservée")
    func aFailureElsewhereNamesTheStuckDay() throws {
        let notice = try #require(
            JournalNotice.notice(
                conflict: nil, writeFailure: "La note n'a pas pu être enregistrée.",
                failingDate: other, displayedDate: displayed
            )
        )
        #expect(
            notice.failure == .elsewhere("La note n'a pas pu être enregistrée.", other)
        )
        let consequence = try #require(notice.failure?.consequence)
        #expect(consequence.contains(Format.fullDate(other.date())))
        #expect(!consequence.contains("ce texte"))
    }

    /// Nothing produces this — the store sets the message and the date
    /// together — but of the two readings, treating it as the note on screen
    /// is the one that cannot send the reader to a day that is not stuck.
    @Test("un échec sans date porte sur la note affichée")
    func aFailureWithoutADateIsReadAsThisNote() throws {
        let notice = try #require(
            JournalNotice.notice(
                conflict: nil, writeFailure: "erreur", failingDate: nil,
                displayedDate: displayed
            )
        )
        #expect(notice.failure == .here("erreur"))
    }

    /// Both at once, on the note on screen: neither can be dropped. Hiding the
    /// banner would let a save that finally goes through overwrite a change
    /// made elsewhere with nothing said; hiding the failure would leave the
    /// reader believing the text is on disk.
    @Test("un conflit et un échec sur la même note se disent tous les deux")
    func aConflictAndAFailureHereBothShow() throws {
        let notice = try #require(
            JournalNotice.notice(
                conflict: .conflict, writeFailure: "erreur",
                failingDate: displayed, displayedDate: displayed
            )
        )
        #expect(notice.conflict == .changedElsewhere)
        #expect(notice.failure == .here("erreur"))
    }

    /// And the precedence that matters: the conflict belongs to the note the
    /// store is still editing, which is the one that failed to write. Left
    /// standing over another note, **Recharger** — which drops the buffer, the
    /// edited date and the baseline unconditionally — would throw away the
    /// text that could not be saved.
    @Test("un échec sur une autre note retire le bandeau de conflit")
    func aFailureElsewhereWithdrawsTheBanner() throws {
        let notice = try #require(
            JournalNotice.notice(
                conflict: .conflict, writeFailure: "erreur",
                failingDate: other, displayedDate: displayed
            )
        )
        #expect(notice.conflict == nil)
        #expect(notice.failure == .elsewhere("erreur", other))
    }
}
