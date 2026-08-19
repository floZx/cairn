import SwiftUI

/// Ce qui est en train d'être tapé après un `@`, s'il y a quelque chose.
///
/// Une fonction pure sur deux chaînes — l'ancienne et la nouvelle — plutôt
/// qu'une lecture du curseur : `TextEditor` ne donne pas la position
/// d'insertion, et la déduire de ce qui a changé marche pour le seul cas qui
/// compte, celui où l'on tape. Retoucher le milieu d'une phrase déjà écrite ne
/// propose rien, ce qui est mieux que de proposer au mauvais endroit.
enum MentionCompletion {
    /// Le pseudo partiel et l'étendue qu'il occupe dans le texte.
    struct EnCours: Equatable {
        /// Ce qui suit le `@`, éventuellement vide juste après l'avoir tapé.
        var fragment: String
        /// Du `@` à la fin du fragment — ce qu'un choix remplacera.
        var plage: Range<String.Index>
    }

    /// Où le texte a changé : la fin de ce qui vient d'être inséré.
    ///
    /// Rend nil quand rien n'a été ajouté — un effacement, un collage qui
    /// remplace tout, un texte identique.
    static func pointDInsertion(de ancien: String, vers nouveau: String) -> String.Index? {
        guard nouveau.count > ancien.count else { return nil }
        var index = nouveau.startIndex
        var ancienIndex = ancien.startIndex
        while index < nouveau.endIndex, ancienIndex < ancien.endIndex,
              nouveau[index] == ancien[ancienIndex] {
            index = nouveau.index(after: index)
            ancienIndex = ancien.index(after: ancienIndex)
        }
        // Ce qui reste de neuf commence ici ; le curseur est à la fin de
        // l'insertion, dont la longueur est la différence des deux tailles.
        let ajoute = nouveau.count - ancien.count
        return nouveau.index(index, offsetBy: ajoute - 1, limitedBy: nouveau.endIndex)
            .map { nouveau.index(after: $0) }
    }

    /// La citation en cours de frappe au point donné, s'il y en a une.
    static func enCours(dans texte: String, a curseur: String.Index) -> EnCours? {
        var debut = curseur
        var fragment = ""
        while debut > texte.startIndex {
            let precedent = texte.index(before: debut)
            let caractere = texte[precedent]
            if caractere == "@" {
                // Le `@` doit ouvrir le mot, comme partout ailleurs : sinon
                // taper une adresse de courriel ouvrirait une liste de gens.
                let avant = precedent > texte.startIndex
                    ? texte[texte.index(before: precedent)] : " "
                guard avant.isWhitespace || "([{«\"'-–—*>".contains(avant) else { return nil }
                return EnCours(fragment: fragment, plage: precedent..<curseur)
            }
            guard PersonHandle.isAllowed(caractere) else { return nil }
            fragment.insert(caractere, at: fragment.startIndex)
            debut = precedent
            // Un pseudo ne fait pas trente caractères : au-delà, c'est qu'on
            // remonte dans du texte ordinaire.
            if fragment.count > 30 { return nil }
        }
        return nil
    }

    /// Les personnes proposées pour un fragment, les plus courtes d'abord.
    ///
    /// Par le début du pseudo et non « contient » : on tape le début d'un
    /// prénom, et une liste qui remonte « Marie » pour « ari » ferait douter de
    /// ce qu'elle cherche.
    static func propositions(
        pour fragment: String, parmi connus: [PersonHandle], limite: Int = 6
    ) -> [PersonHandle] {
        let cherche = PersonHandle.replie(fragment)
        return connus
            .filter { cherche.isEmpty || $0.key.hasPrefix(cherche) }
            .sorted {
                $0.name.count != $1.name.count
                    ? $0.name.count < $1.name.count : $0 < $1
            }
            .prefix(limite)
            .map { $0 }
    }

    /// Le texte, la citation choisie mise à la place du fragment.
    static func complete(
        _ texte: String, remplacant plage: Range<String.Index>, par handle: PersonHandle
    ) -> String {
        texte.replacingCharacters(in: plage, with: "@\(handle.name) ")
    }
}
