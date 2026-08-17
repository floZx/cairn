import Testing
import Foundation
@testable import Cairn

/// Ce que la reprise a le droit de dire, et comment elle le dit. Tenu à la
/// lettre ici parce que la vue, elle, ne peut pas être interrogée : ces
/// phrases sont la seule trace qu'un lecteur reçoit d'une reprise imparfaite
/// ou impossible.
@Suite("JournalNotice")
struct JournalNoticeTests {
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
        let message = try #require(JournalNotice.notice(unreadable: ["2026-08-17.md"])?.message)
        #expect(message.contains("1 fichier"))
        #expect(!message.contains("1 fichiers"))
        #expect(message.contains("2026-08-17.md"))
    }

    /// Plusieurs : l'accord passe au pluriel, et chaque nom est repris —
    /// aucun n'est sacrifié pour la brièveté du message.
    @Test("plusieurs fichiers illisibles se disent au pluriel et sont tous nommés")
    func severalUnreadableFilesArePluralAndAllNamed() throws {
        let message = try #require(
            JournalNotice.notice(unreadable: ["2026-08-15.md", "2026-08-17-1.jpg"])?.message
        )
        #expect(message.contains("2 fichiers"))
        #expect(message.contains("2026-08-15.md"))
        #expect(message.contains("2026-08-17-1.jpg"))
    }

    /// Une reprise qui n'a pas pu s'exécuter nomme le dossier : c'est la seule
    /// indication qui reste au lecteur, le sélecteur de dossier ayant disparu
    /// avec le dossier lui-même.
    @Test("une reprise impossible nomme le dossier et annonce une nouvelle tentative")
    func aFailedRecoveryNamesTheFolder() {
        let message = JournalNotice.notice(recoveryFailure: "/Volumes/Passeport/Journal").message
        #expect(message.contains("/Volumes/Passeport/Journal"))
        #expect(message.contains("prochain lancement"))
    }

    /// Sans chemin enregistré, il n'y a pas de dossier à nommer — et une
    /// phrase citant des guillemets vides serait pire que la phrase courte.
    @Test("sans dossier enregistré, la phrase reste courte")
    func aFailedRecoveryWithoutAFolderStaysShort() {
        let message = JournalNotice.notice(recoveryFailure: nil).message
        #expect(!message.contains("«"))
        #expect(message.contains("prochain lancement"))
    }
}
