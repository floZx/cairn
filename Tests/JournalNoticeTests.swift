import Testing
import Foundation
@testable import Cairn

/// The mapping from the store's state to what the editor's header says, and to
/// which buttons it offers. Held to the letter here because the view cannot be
/// asked: a **Recharger** shown over the wrong note discards a buffer.
@Suite("JournalNotice")
struct JournalNoticeTests {
    @Test("rien à signaler ne pose aucun bandeau")
    func nothingWrongSaysNothing() {
        #expect(JournalNotice.notice(conflict: nil) == nil)
    }

    @Test("une note modifiée ailleurs propose de recharger")
    func aChangedNoteOffersToReload() throws {
        let notice = try #require(JournalNotice.notice(conflict: .conflict))
        #expect(notice.conflict == .changedElsewhere)
        #expect(notice.message == nil)
        #expect(notice.conflict?.offersReload == true)
        #expect(
            notice.conflict?.message
                == "La note a été modifiée ailleurs. Votre texte est conservé ici."
        )
    }

    @Test("un fichier supprimé ailleurs ne propose rien à recharger")
    func aDeletedFileHasNothingToReload() throws {
        let notice = try #require(JournalNotice.notice(conflict: .vanished))
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
        #expect(JournalNotice.notice(conflict: .adopt) == nil)
    }

    // MARK: - Le rapport de la reprise

    /// Rien d'illisible : la reprise n'a rien à signaler, et un message vide
    /// serait un mensonge de plus que le silence.
    @Test("une reprise sans fichier illisible ne dit rien")
    func aCleanRecoverySaysNothing() {
        #expect(JournalNotice.notice(unreadable: []) == nil)
    }

    /// Un seul fichier : l'accord se fait au singulier, et son nom apparaît
    /// dans le message — sans quoi le lecteur ne saurait pas lequel regarder.
    @Test("un seul fichier illisible se dit au singulier et le nomme")
    func oneUnreadableFileIsNamedAndSingular() throws {
        let notice = try #require(JournalNotice.notice(unreadable: ["2026-08-17.md"]))
        #expect(notice.conflict == nil)
        let message = try #require(notice.message)
        #expect(message.contains("1 fichier"))
        #expect(!message.contains("1 fichiers"))
        #expect(message.contains("2026-08-17.md"))
    }

    /// Plusieurs : l'accord passe au pluriel, et chaque nom est repris —
    /// aucun n'est sacrifié pour la brièveté du message.
    @Test("plusieurs fichiers illisibles se disent au pluriel et sont tous nommés")
    func severalUnreadableFilesArePluralAndAllNamed() throws {
        let notice = try #require(
            JournalNotice.notice(unreadable: ["2026-08-15.md", "2026-08-17-1.jpg"])
        )
        let message = try #require(notice.message)
        #expect(message.contains("2 fichiers"))
        #expect(message.contains("2026-08-15.md"))
        #expect(message.contains("2026-08-17-1.jpg"))
    }

    /// Une reprise qui n'a pas pu s'exécuter nomme le dossier : c'est la seule
    /// indication qui reste au lecteur, le sélecteur de dossier ayant disparu
    /// avec le dossier lui-même.
    @Test("une reprise impossible nomme le dossier et annonce une nouvelle tentative")
    func aFailedRecoveryNamesTheFolder() throws {
        let notice = JournalNotice.notice(recoveryFailure: "/Volumes/Passeport/Journal")
        let message = try #require(notice.message)
        #expect(message.contains("/Volumes/Passeport/Journal"))
        #expect(message.contains("prochain lancement"))
    }

    /// Sans chemin enregistré, il n'y a pas de dossier à nommer — et une
    /// phrase citant des guillemets vides serait pire que la phrase courte.
    @Test("sans dossier enregistré, la phrase reste courte")
    func aFailedRecoveryWithoutAFolderStaysShort() throws {
        let message = try #require(JournalNotice.notice(recoveryFailure: nil).message)
        #expect(!message.contains("«"))
        #expect(message.contains("prochain lancement"))
    }
}
