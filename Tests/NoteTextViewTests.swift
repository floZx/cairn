import Testing
import AppKit
@testable import Cairn

/// La règle qui décide si le champ de note reprend la chaîne de SwiftUI.
@Suite("Le champ de note")
@MainActor
struct NoteTextViewTests {
    private func champ(_ contenu: String) -> NSTextView {
        let champ = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        champ.string = contenu
        return champ
    }

    @Test("un texte venu d'ailleurs est repris")
    func reecritQuandLeTexteDiffere() {
        #expect(NoteTextView.doitReecrire(champ("avant"), texte: "après"))
    }

    @Test("le texte qu'on vient de taper n'est pas réécrit")
    func neReecritPasLIdentique() {
        #expect(!NoteTextView.doitReecrire(champ("pareil"), texte: "pareil"))
    }

    /// Le `^` d'un clavier français pose du texte marqué, que la touche
    /// suivante remplacera par « ê ». Réécrire entre les deux abandonne la
    /// composition, et l'accent devient impossible à saisir.
    @Test("une composition en cours n'est jamais interrompue")
    func neReecritPasPendantUneComposition() {
        let champ = champ("un accent : ")
        champ.setMarkedText(
            "^", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 12, length: 0)
        )
        #expect(champ.hasMarkedText())
        // Le texte de SwiftUI a un cycle de retard : il ne porte pas encore le
        // `^`. C'est exactement la course qui cassait la saisie.
        #expect(!NoteTextView.doitReecrire(champ, texte: "un accent : "))
    }
}
