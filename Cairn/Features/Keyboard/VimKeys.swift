import SwiftUI

/// Turns key presses into `VimCommand`s for whichever view is on screen.
///
/// Extracted from the list because the list is not always what is showing: the
/// statistics and the global map can both open the detail pane now, so both must
/// be able to close it again. A handler that lives only on the table works in
/// exactly one of the three places.
///
/// Each view gets its own buffer, which is what we want: a count typed in one
/// view has no business surviving a jump to another.
struct VimKeys: ViewModifier {
    /// Returns whether the command was acted on. A view that cannot carry one
    /// out says so, and the press falls through rather than being swallowed.
    let onCommand: (VimCommand) -> Bool

    /// `onKeyPress` fires while the view *or any descendant* has focus — and a
    /// sheet presented from inside the view is a descendant. Without this
    /// gate, letters typed into such a sheet's text fields ran vim commands
    /// (`n` opened the activity editor) and digits vanished into a count. The
    /// presenting view knows when its sheets are up; the modifier cannot.
    var enabled: Bool = true

    /// Bumped by the caller to bring the keyboard back here.
    ///
    /// A counter rather than a boolean: the request is an event, and a flag that
    /// has to be lowered again is a flag someone forgets to lower.
    ///
    /// It goes through SwiftUI's own focus and not AppKit's. Making the table
    /// first responder does move the insertion point, but `onKeyPress` is driven
    /// by `FocusState`, which knows nothing of it — so the keys stayed dead
    /// exactly as if nothing had been focused at all.
    var focusRequest: Int = 0

    /// Si la vue prend le clavier en apparaissant — posé par l'écran, à
    /// travers l'environnement. Voir `EnvironmentValues.vimKeysClaimentLeFocus`.
    @Environment(\.vimKeysClaimentLeFocus) private var claimsFocusOnAppear

    /// Un compteur qu'on incrémente pour réclamer le clavier depuis ailleurs —
    /// aujourd'hui, la touche Entrée de la barre latérale. Voir
    /// `EnvironmentValues.vimKeysDemandeDeFocus`.
    @Environment(\.vimKeysDemandeDeFocus) private var demandeDeFocus

    @State private var buffer = VimKeyBuffer()
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            // No ring: these views are not form controls, and a focus ring
            // around a whole pane reads as a bug.
            .focusEffectDisabled()
            .focused($focused)
            .onChange(of: focusRequest) { _, _ in focused = true }
            .onChange(of: demandeDeFocus) { _, _ in focused = true }
            // Claim focus on appearance: a `g` jump builds a fresh view, and
            // without this the keys stay dead until the user clicks into the
            // content. One tick later, because the focus system silently drops
            // a target that is still being inserted.
            //
            // Sauf après un clic dans la barre latérale — voir
            // `claimsFocusOnAppear`. Le clavier reste alors où le clic l'a mis,
            // comme dans n'importe quelle application du système : on ne prend
            // pas le clavier à qui vient de s'en servir.
            .onAppear {
                guard claimsFocusOnAppear else { return }
                Task { @MainActor in focused = true }
            }
            // `.repeat` as well as `.down`: without it a held key fires once and
            // walking a long list means tapping `j` eighty times.
            .onKeyPress(phases: [.down, .repeat]) { press in
                guard enabled else { return .ignored }
                guard let character = press.characters.first else { return .ignored }
                // ⌘ belongs to the menus. Swallowing it here would shadow every
                // shortcut the app already publishes.
                guard !press.modifiers.contains(.command) else { return .ignored }

                let control = press.modifiers.contains(.control)
                // A repeat only reaches the buffer for the keys meant to repeat,
                // so a leaned-on digit cannot build a count nobody typed.
                if press.phase == .repeat,
                   !VimKeyBuffer.repeatsWhenHeld(character, control: control) {
                    return .ignored
                }

                guard let command = buffer.accept(character, control: control) else {
                    // A digit or a `g` was consumed even though nothing ran, and
                    // saying so is what stops it reaching a table's type-select.
                    return buffer.isEmpty ? .ignored : .handled
                }
                return onCommand(command) ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                guard enabled else { return .ignored }
                buffer.reset()
                return onCommand(.clear) ? .handled : .ignored
            }
    }
}

extension View {
    func vimKeys(
        enabled: Bool = true, focusRequest: Int = 0,
        _ onCommand: @escaping (VimCommand) -> Bool
    ) -> some View {
        modifier(VimKeys(
            onCommand: onCommand, enabled: enabled, focusRequest: focusRequest
        ))
    }
}

/// Si les vues de contenu prennent le clavier en apparaissant.
///
/// Faux quand la section vient d'être choisie **à la souris** dans la barre
/// latérale. Une liste macOS ne peint sa sélection en bleu vif que lorsqu'elle
/// tient le clavier ; le lui prendre un tick après le clic faisait pâlir la
/// ligne qu'on venait de choisir, sous les yeux de l'utilisateur : bleu, puis
/// le contenu s'affiche, puis le bleu s'en va. Signalé le 31 août 2026, et
/// « un peu aléatoire » parce que c'est une course entre ce tick et le clic.
///
/// Par l'environnement plutôt que par un argument : le réglage vaut pour
/// toutes les vues de la colonne de contenu, dont quatre reçoivent `vimKeys`
/// chez elles — leur faire porter le réglage aurait demandé de le passer à
/// travers quatre signatures qui n'ont rien à voir avec le focus.
///
/// Vrai par défaut, donc au clavier — `gj`, `gd` — où le focus était déjà dans
/// le contenu et doit y rester : c'est le seul cas où le réclamer ne prend rien
/// à personne.
extension EnvironmentValues {
    @Entry var vimKeysClaimentLeFocus = true
}

/// Réclame le clavier pour la vue de contenu, de l'extérieur.
///
/// Un compteur et non un booléen : ce qui se demande est un *geste*, pas un
/// état, et deux gestes de suite doivent tous deux arriver.
///
/// Son unique usager est la touche Entrée de la barre latérale. Depuis que le
/// contenu ne prend plus le clavier après un clic — voir
/// `vimKeysClaimentLeFocus` — la barre le garde, ce qui est juste, mais laissait
/// `j` et `k` sans effet jusqu'au premier clic dans la liste. Entrée fait ce
/// passage, comme la tabulation le fait ailleurs dans le système : on choisit
/// une section, on valide, on est dedans.
extension EnvironmentValues {
    @Entry var vimKeysDemandeDeFocus = 0
}
