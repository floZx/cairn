import Foundation

/// Les deux façons de lire le journal : par journée, ou par personne.
///
/// Les gens avaient leur ligne dans la barre latérale, entre le journal et
/// l'alimentation, c'est-à-dire parmi des sections qui sont des *endroits*.
/// Mais ce n'en est pas un : ce sont les mêmes notes, rangées par qui y est
/// cité plutôt que par le jour où on les a écrites — la liste des gens se
/// vide d'ailleurs avec le journal. La version mobile le dit ainsi depuis le
/// début, avec un sélecteur sur la ligne du titre ; ici c'est le même choix,
/// dans la barre d'outils, à côté du sélecteur de présentation des activités.
enum VueJournal: String, CaseIterable, Identifiable {
    case journees
    case gens

    /// La vue choisie se retient d'une fois sur l'autre : c'est une façon de
    /// lire, comme le tableau ou les fiches côté activités, pas un endroit où
    /// l'on passe.
    static let storageKey = "journalVue"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .journees: "Journées"
        case .gens: "People"
        }
    }

    /// Les mêmes dessins que sur mobile : le carnet, et l'arobase qui fait la
    /// fonctionnalité.
    var symbolName: String {
        switch self {
        case .journees: "text.book.closed"
        case .gens: "at"
        }
    }
}
