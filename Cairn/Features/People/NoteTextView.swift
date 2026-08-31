import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Un champ de note adossé à un `NSTextView`.
///
/// `TextEditor` en est déjà un sous le capot : on ne gagne donc aucune
/// capacité en descendant d'un étage — l'annulation, le correcteur, les emoji
/// et le glisser-déposer viennent de la classe AppKit, pas de SwiftUI. Ce
/// qu'on vient chercher est **le rectangle du curseur**, que SwiftUI n'expose
/// pas, et sans lequel une liste de complétion ne peut que se poser à un
/// endroit fixe — ce qui se voyait, et se lisait comme un bricolage.
///
/// Ce que ce fichier reprend à sa charge, et qui était gratuit avant : le
/// premier répondant, la synchronisation du texte, les touches, et le collage
/// d'une image.
struct NoteTextView: NSViewRepresentable {
    @Binding var texte: String
    var taille: CGFloat
    /// Vrai quand l'éditeur doit avoir le clavier.
    @Binding var focus: Bool
    /// Où poser le curseur, en unités UTF-16, quand quelqu'un le demande —
    /// après l'insertion d'une citation. Remis à `nil` une fois posé.
    @Binding var curseurDemande: Int?

    /// Les touches que la complétion peut vouloir intercepter. Rendre `true`
    /// les consomme ; `false` les laisse à l'éditeur, où elles gardent leur
    /// sens ordinaire.
    var onCommande: (Commande) -> Bool
    /// Le rectangle du curseur, dans les coordonnées de cette vue.
    var onCurseur: (CGRect) -> Void
    /// Une image collée. Rendre `true` la consomme.
    var onImageCollee: (Data) -> Bool

    enum Commande { case tabulation, haut, bas, echappement }

    func makeNSView(context: Context) -> NSScrollView {
        // Monté à la main plutôt que par `scrollableTextView()` : cette
        // fabrique rend bien une vue de la classe qui l'appelle, mais rien
        // dans sa signature ne le promet, et tout le collage d'image en
        // dépend. Quinze lignes contre une supposition.
        let champ = ChampDeNote()
        champ.autoresizingMask = [.width]
        champ.isVerticallyResizable = true
        champ.isHorizontallyResizable = false
        champ.textContainer?.widthTracksTextView = true
        champ.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        champ.minSize = NSSize(width: 0, height: 0)
        champ.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)

        let defilement = NSScrollView()
        defilement.documentView = champ
        defilement.drawsBackground = false
        defilement.hasVerticalScroller = true
        defilement.autohidesScrollers = true

        champ.delegate = context.coordinator
        champ.drawsBackground = false
        champ.isRichText = false
        champ.allowsUndo = true
        champ.isAutomaticQuoteSubstitutionEnabled = true
        champ.isContinuousSpellCheckingEnabled = true
        champ.textContainerInset = NSSize(width: 8, height: 8)
        champ.font = .systemFont(ofSize: taille)
        champ.string = texte
        champ.surImage = onImageCollee

        context.coordinator.champ = champ
        context.coordinator.defilement = defilement
        return defilement
    }

    func updateNSView(_ defilement: NSScrollView, context: Context) {
        guard let champ = defilement.documentView as? ChampDeNote else { return }
        context.coordinator.parent = self
        champ.surImage = onImageCollee
        champ.font = .systemFont(ofSize: taille)

        // **Le point délicat de tout `NSViewRepresentable` de champ texte.**
        //
        // Réécrire la chaîne pendant la frappe replace le curseur au début :
        // c'est le défaut que tout le monde rencontre ici. On ne touche donc
        // au texte que lorsqu'il diffère vraiment — un changement venu
        // d'ailleurs, jamais celui qu'on vient de taper — et la sélection est
        // rétablie derrière. Voir `doitReecrire` pour le second cas, moins
        // connu, où il ne faut pas y toucher non plus.
        if Self.doitReecrire(champ, texte: texte) {
            let selection = champ.selectedRange()
            champ.string = texte
            let borne = min(selection.location, (texte as NSString).length)
            champ.setSelectedRange(NSRange(location: borne, length: 0))
        }

        if let position = curseurDemande {
            let borne = min(position, (champ.string as NSString).length)
            champ.setSelectedRange(NSRange(location: borne, length: 0))
            champ.scrollRangeToVisible(champ.selectedRange())
            // Après la mise à jour : remettre l'état à zéro pendant qu'on la
            // calcule est ce que SwiftUI refuse.
            DispatchQueue.main.async { curseurDemande = nil }
        }

        if focus, champ.window?.firstResponder !== champ {
            // Au tour suivant : demander le premier répondant pendant la mise
            // à jour d'une vue qui n'est pas encore dans une fenêtre ne fait
            // rien du tout, silencieusement.
            DispatchQueue.main.async { champ.window?.makeFirstResponder(champ) }
        }
    }

    /// Si la chaîne du champ doit être remplacée par celle que SwiftUI tient.
    ///
    /// Différente ne suffit pas : **pas pendant une composition**. Une touche
    /// morte — le `^` d'un clavier français, avant le `e` de « ê » — pose du
    /// *texte marqué* dans le champ, que la méthode de saisie remplacera par
    /// le caractère composé à la touche suivante. Écrire `string` entre les
    /// deux abandonne la composition : le `^` disparaît, et le `e` arrive nu.
    /// Signalé le 31 août 2026 — aucun accent circonflexe n'était saisissable
    /// dans le moindre champ de note.
    ///
    /// Et la course est difficile à perdre : dans le journal, chaque frappe
    /// remonte jusqu'au magasin et redescend, si bien qu'une mise à jour
    /// arrive presque à coup sûr entre les deux touches, avec un `texte` d'un
    /// cycle de retard — donc différent, donc réécrit.
    ///
    /// À part et non `hasMarkedText()` glissé dans la condition : c'est la
    /// règle qui porte le défaut, et une règle s'éprouve.
    static func doitReecrire(_ champ: NSTextView, texte: String) -> Bool {
        champ.string != texte && !champ.hasMarkedText()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        weak var champ: NSTextView?
        weak var defilement: NSScrollView?

        init(parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let champ else { return }
            parent.texte = champ.string
            signalerLeCurseur()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            signalerLeCurseur()
        }

        // Le focus se raconte dans les deux sens.
        //
        // Sans ça, une vue qui se met à jour pour une autre raison reprendrait
        // le clavier à qui l'a pris entre-temps : `focus` serait resté vrai
        // alors que le champ ne l'a plus.
        func textDidBeginEditing(_ notification: Notification) {
            if !parent.focus { parent.focus = true }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.focus { parent.focus = false }
        }

        func textView(
            _ textView: NSTextView, doCommandBy commandeSélecteur: Selector
        ) -> Bool {
            switch commandeSélecteur {
            case #selector(NSResponder.insertTab(_:)):
                return parent.onCommande(.tabulation)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onCommande(.bas)
            case #selector(NSResponder.moveUp(_:)):
                return parent.onCommande(.haut)
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.onCommande(.echappement) { return true }
                // Personne n'en veut : le champ rend le clavier plutôt que de
                // laisser AppKit faire son geste par défaut, qui est d'ouvrir
                // **sa** complétion de texte — la dernière chose à montrer
                // à quelqu'un qui vient d'en refuser une.
                textView.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        /// Le rectangle du curseur, dans les coordonnées de la vue SwiftUI.
        ///
        /// Passé par le gestionnaire de disposition plutôt que par
        /// `firstRect(forCharacterRange:)`, qui rend des coordonnées d'écran
        /// qu'il faudrait ensuite ramener à travers la fenêtre — deux
        /// conversions au lieu d'une, et une de plus à se tromper.
        private func signalerLeCurseur() {
            guard let champ, let defilement,
                  let disposition = champ.layoutManager,
                  let conteneur = champ.textContainer
            else { return }
            let selection = champ.selectedRange()
            let glyphes = disposition.glyphRange(
                forCharacterRange: NSRange(location: selection.location, length: 0),
                actualCharacterRange: nil
            )
            var rect = disposition.boundingRect(forGlyphRange: glyphes, in: conteneur)
            rect.origin.x += champ.textContainerOrigin.x
            rect.origin.y += champ.textContainerOrigin.y
            // Une ligne vide rend un rectangle sans largeur : de quoi poser
            // quelque chose contre, tout de même.
            if rect.width < 1 { rect.size.width = 1 }
            parent.onCurseur(champ.convert(rect, to: defilement))
        }
    }
}

/// Le champ lui-même, pour la seule chose qu'un `NSTextView` fait autrement :
/// le collage.
///
/// Il mange ⌘V avant que SwiftUI ne le voie, et le journal en avait besoin —
/// `onPasteCommand` recevait jusqu'ici les images collées dans la note.
/// Rendues au champ, elles y seraient devenues du texte, ou rien.
final class ChampDeNote: NSTextView {
    var surImage: ((Data) -> Bool)?

    override func paste(_ sender: Any?) {
        let presse = NSPasteboard.general
        for type in [UTType.png, .jpeg, .heic] {
            guard let data = presse.data(forType: NSPasteboard.PasteboardType(type.identifier))
            else { continue }
            if surImage?(data) == true { return }
        }
        super.paste(sender)
    }
}
