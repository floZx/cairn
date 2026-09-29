import Foundation
import SwiftData

/// Renommer quelqu'un : réécrire chaque `@ancien` en `@nouveau`, partout.
///
/// Une personne n'existe que par les textes qui la citent — voir `Person`.
/// Changer son nom, c'est donc changer ces textes : les notes du journal,
/// celles des sorties, des repas, des pesées, et le nom de sa fiche. Le cas
/// qui l'a fait naître : une seconde Stéphanie arrive, et la première doit
/// devenir « Stéphanie-M » pour que les deux ne se confondent pas.
enum PersonRename {
    enum Refus: Equatable {
        /// Ce n'est pas un nom qu'une mention accepte.
        case nomInvalide
        /// Le même nom, rien à faire.
        case inchange
        /// Quelqu'un d'autre le porte déjà : c'est une fusion, pas un
        /// renommage — voir `PersonAliases.fusionner`.
        case dejaPris(PersonHandle)
    }

    /// Le texte avec chaque mention de `ancien` réécrite en `nouveau`, ou nil
    /// quand il ne la cite pas.
    ///
    /// Reconnue par la règle de `PersonScanner` : l'arobase ouvre le mot, si
    /// bien qu'une adresse de courriel n'est jamais touchée ; et par la clé,
    /// si bien que « @stephanie » tapé à la hâte est réécrit aussi.
    static func remplacer(
        dans texte: String, ancien: PersonHandle, par nouveau: PersonHandle
    ) -> String? {
        var resultat = ""
        var change = false
        var precedent: Character?
        var index = texte.startIndex
        while index < texte.endIndex {
            let caractere = texte[index]
            if caractere == "@",
               precedent == nil || precedent!.isWhitespace || "([{«\"'-–—*>".contains(precedent!) {
                let debut = texte.index(after: index)
                let fin = texte[debut...].firstIndex { !PersonHandle.isAllowed($0) } ?? texte.endIndex
                if let cite = PersonHandle(name: String(texte[debut..<fin])), cite.key == ancien.key {
                    resultat += "@" + nouveau.name
                    change = true
                    precedent = nouveau.name.last
                    index = fin
                    continue
                }
            }
            resultat.append(caractere)
            precedent = caractere
            index = texte.index(after: index)
        }
        return change ? resultat : nil
    }

    /// Ce qui empêche de donner ce nom, ou nil quand rien.
    ///
    /// `connus` : toutes les personnes citées ou fichées, alias compris.
    static func refus(
        _ nom: String, pour ancien: PersonHandle, connus: [PersonHandle]
    ) -> Refus? {
        let propre = nom.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        guard let nouveau = PersonHandle(name: propre) else { return .nomInvalide }
        if nouveau.name == ancien.name { return .inchange }
        if nouveau.key != ancien.key,
           let autre = connus.first(where: { $0.key == nouveau.key }) {
            return .dejaPris(autre)
        }
        return nil
    }

    /// Réécrit tout ce qui cite `ancien` — hors journal, que `JournalStore`
    /// réécrit lui-même pour que la note ouverte suive —, et renomme sa
    /// fiche.
    ///
    /// - Returns: le nombre de textes réécrits.
    @discardableResult
    static func renommer(
        _ ancien: PersonHandle, en nouveau: PersonHandle, context: ModelContext
    ) -> Int {
        var reecrits = 0

        // Les sorties par leur brouillon, jamais en direct : c'est lui qui
        // marque la note comme modifiée, sans quoi la synchronisation Strava
        // suivante la réécrirait — voir `ActivityDraft`.
        let decrites = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.activityDescription != nil }
        )
        for sortie in (try? context.fetch(decrites)) ?? [] {
            guard let texte = sortie.activityDescription,
                  let neuf = remplacer(dans: texte, ancien: ancien, par: nouveau)
            else { continue }
            var brouillon = ActivityDraft(sortie)
            brouillon.notes = neuf
            brouillon.apply(to: sortie)
            reecrits += 1
        }
        for repas in (try? context.fetch(FetchDescriptor<MealNote>())) ?? [] {
            guard let neuf = remplacer(dans: repas.note, ancien: ancien, par: nouveau) else { continue }
            repas.note = neuf
            reecrits += 1
        }
        for pesee in (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? [] {
            guard let texte = pesee.note,
                  let neuf = remplacer(dans: texte, ancien: ancien, par: nouveau)
            else { continue }
            pesee.note = neuf
            reecrits += 1
        }
        let fiches = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        for fiche in fiches {
            // Sa note, et celles des autres qui la citeraient.
            if let neuf = remplacer(dans: fiche.note, ancien: ancien, par: nouveau) {
                fiche.note = neuf
            }
        }
        if let fiche = fiches.first(where: { $0.key == ancien.key }) {
            fiche.name = nouveau.name
            fiche.key = nouveau.key
        }
        return reecrits
    }
}
