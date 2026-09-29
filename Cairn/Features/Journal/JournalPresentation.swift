import Foundation

/// Ce qu'une journée montre dans la liste du journal : tout, ou son texte seul.
///
/// Le pendant des présentations de fiches côté activités, et rangé au même
/// endroit, dans le menu Présentation.
enum JournalPresentation: String, CaseIterable, Identifiable, Sendable {
    /// La colonne de droite : étiquettes, sports, pesée, vignettes.
    case complete
    /// La tuile du jour et le texte, rien à droite.
    case epuree

    static let storageKey = "journalPresentation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .complete: "Complète"
        case .epuree: "Épurée"
        }
    }
}
