import Foundation
import SwiftData

/// Ce qu'on fait des alias : en donner un à quelqu'un, ou le lui reprendre.
///
/// Donner un alias et fusionner deux personnes sont le même geste. « Chris est
/// aussi Christèle » : si Chris avait sa fiche, sa note rejoint celle de
/// Christèle et ses propres alias la suivent, puis sa fiche disparaît — il
/// n'est plus qu'un autre nom. S'il n'en avait pas, il devient simplement un
/// alias.
///
/// Des fonctions sur les fiches plutôt que sur l'écran, pour que les deux
/// endroits qui le font — la ligne « Aussi appelée » et le menu de la liste —
/// fassent la même chose, et qu'elle s'éprouve sans vue.
enum PersonAliases {
    /// Ramène `source` à `cible` : désormais un alias de sa fiche.
    ///
    /// - Returns: faux quand il n'y a rien à faire — la même personne, ou un
    ///   nom qui n'en est pas un.
    @discardableResult
    static func fusionner(
        _ source: PersonHandle, dans cible: PersonHandle, context: ModelContext
    ) -> Bool {
        guard source.key != cible.key else { return false }
        let fiches = (try? context.fetch(FetchDescriptor<Person>())) ?? []

        let ficheCible: Person
        if let existante = fiches.first(where: { $0.key == cible.key }) {
            ficheCible = existante
        } else {
            ficheCible = Person(handle: cible)
            context.insert(ficheCible)
        }

        var alias = ficheCible.aliases
        func ajoute(_ nom: String) {
            guard let handle = PersonHandle(name: nom), handle.key != cible.key,
                  !alias.contains(where: { PersonHandle(name: $0)?.key == handle.key })
            else { return }
            alias.append(handle.name)
        }
        ajoute(source.name)

        for autre in fiches where autre !== ficheCible {
            if autre.key == source.key {
                // Sa fiche se fond dans l'autre : ses alias, puis sa note, à la
                // suite de ce qui y était déjà.
                autre.aliases.forEach(ajoute)
                let note = autre.note.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    let existante = ficheCible.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    ficheCible.note = existante.isEmpty ? autre.note : ficheCible.note + "\n\n" + autre.note
                }
                context.delete(autre)
            } else if autre.aliases.contains(where: { PersonHandle(name: $0)?.key == source.key }) {
                // Un nom ne désigne qu'une personne : il quitte celle qui le
                // portait.
                autre.aliases.removeAll { PersonHandle(name: $0)?.key == source.key }
                supprimerSiVide(autre, context: context)
            }
        }

        ficheCible.aliases = alias
        return true
    }

    /// Reprend un alias à sa fiche. Le nom redevient une personne à part
    /// entière, dans la liste, dès qu'une note le cite.
    static func retirer(_ alias: PersonHandle, de fiche: Person, context: ModelContext) {
        fiche.aliases.removeAll { PersonHandle(name: $0)?.key == alias.key }
        supprimerSiVide(fiche, context: context)
    }

    /// Une fiche sans note ni alias n'a plus rien à porter : la laisser ferait
    /// rester quelqu'un dans la liste alors que plus rien ne le décrit.
    static func supprimerSiVide(_ fiche: Person, context: ModelContext) {
        let note = fiche.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty, fiche.aliases.isEmpty { context.delete(fiche) }
    }
}
