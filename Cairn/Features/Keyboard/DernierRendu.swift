import Foundation

/// Les lignes et la sélection du dernier rendu d'une liste, pour son
/// gestionnaire de touches.
///
/// Ce gestionnaire est une fermeture que SwiftUI ne remplace pas toujours
/// quand la vue est redessinée : il peut garder une copie de la vue antérieure
/// à l'arrivée d'une ligne. Relevé le 3 octobre 2026 dans la liste des
/// activités — elle montrait 812 sorties, la nouvelle en tête, et `k`
/// travaillait encore sur les 811 d'avant : il butait sur l'ancienne première
/// et la nouvelle restait hors d'atteinte. Ce n'est pas systématique, d'où un
/// défaut vu deux jours de suite puis introuvable à l'essai.
///
/// Dans cette copie périmée, un `@State` se lit à jour — il pointe vers un
/// stockage vivant — mais un `let` calculé par le corps et une `Binding` reçue
/// du parent sont figés. Tenue par `@State`, cette classe est la même instance
/// pour toutes les copies de la vue, vieilles comprises : le corps y dépose ce
/// qu'il vient de calculer, et le gestionnaire lit là plutôt que dans ce qu'il
/// a capturé.
///
/// Pas observée, et c'est voulu : y écrire pendant le rendu ne doit pas en
/// provoquer un autre.
@MainActor
final class DernierRendu<Lignes, Selection> {
    var lignes: Lignes
    var selection: Selection

    init(lignes: Lignes, selection: Selection) {
        self.lignes = lignes
        self.selection = selection
    }

    /// Appelé par le corps, à chaque rendu.
    func retenir(_ lignes: Lignes, selection: Selection) {
        self.lignes = lignes
        self.selection = selection
    }
}
