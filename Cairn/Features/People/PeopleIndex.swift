import Foundation
import SwiftData

/// Qui est cité, où, et quand.
///
/// Construit à la volée depuis les textes, jamais rangé : c'est le même parti
/// que `JournalTagScanner`, et `Person` dit pourquoi. Une fonction pure sur des
/// valeurs plates plutôt que sur les modèles, pour qu'elle s'éprouve sans
/// magasin — c'est la seule partie de People qui puisse se tromper en silence.
enum PeopleIndex {
    /// D'où vient une citation. Le libellé est ce que l'écran affiche au-dessus
    /// de l'extrait.
    enum Source: Equatable {
        case journal
        case sortie(String)
        case repas(String)
        case pesee
        case seance(String)

        var libelle: String {
            switch self {
            case .journal: "Journal"
            case .sortie(let nom): nom
            case .repas(let creneau): creneau
            case .pesee: "Pesée"
            case .seance(let titre): titre
            }
        }
    }

    /// Un texte qui cite quelqu'un.
    struct Citation: Identifiable, Equatable {
        var dateKey: DateKey
        var source: Source
        var texte: String
        /// La sortie à ouvrir, quand la citation vient de sa note.
        var activityUUID: String?

        var id: String { "\(dateKey.raw)|\(source.libelle)|\(texte.hashValue)" }
    }

    /// Un texte à examiner, réduit à ce dont l'index a besoin.
    struct Texte {
        var dateKey: DateKey
        var source: Source
        var contenu: String
        var activityUUID: String?

        init(
            dateKey: DateKey, source: Source, contenu: String, activityUUID: String? = nil
        ) {
            self.dateKey = dateKey
            self.source = source
            self.contenu = contenu
            self.activityUUID = activityUUID
        }
    }

    /// Les citations de chacun, les plus récentes d'abord.
    ///
    /// Une personne citée deux fois dans le même texte n'y figure qu'une : on
    /// veut la liste des notes qui parlent d'elle, pas celle des occurrences.
    static func citations(dans textes: [Texte]) -> [PersonHandle: [Citation]] {
        var index: [PersonHandle: [Citation]] = [:]
        for texte in textes {
            let propre = texte.contenu.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !propre.isEmpty else { continue }
            for handle in PersonScanner.mentions(in: propre) {
                index[handle, default: []].append(
                    Citation(
                        dateKey: texte.dateKey, source: texte.source, texte: propre,
                        activityUUID: texte.activityUUID
                    )
                )
            }
        }
        for (handle, citations) in index {
            index[handle] = citations.sorted { gauche, droite in
                gauche.dateKey.raw != droite.dateKey.raw
                    ? gauche.dateKey.raw > droite.dateKey.raw
                    : gauche.source.libelle < droite.source.libelle
            }
        }
        return index
    }

    /// Une ligne de la liste des gens.
    struct Ligne: Identifiable, Equatable {
        var handle: PersonHandle
        var compte: Int
        /// La citation la plus récente, pour dater la ligne.
        var derniere: DateKey?
        /// Vrai quand une fiche existe déjà — donc quand quelque chose a été
        /// écrit sur elle.
        var aUneNote: Bool

        var id: String { handle.key }
    }

    /// La liste, la plus récemment citée d'abord.
    ///
    /// Les personnes dont la fiche existe mais qu'aucune note ne cite plus y
    /// figurent quand même, en bas : on a écrit quelque chose sur elles, et le
    /// perdre parce qu'une note a été retouchée serait une trappe.
    static func lignes(
        citations: [PersonHandle: [Citation]], fiches: [(key: String, name: String)]
    ) -> [Ligne] {
        var lignes = citations.map { handle, citees in
            Ligne(
                handle: handle, compte: citees.count, derniere: citees.first?.dateKey,
                aUneNote: fiches.contains { $0.key == handle.key }
            )
        }
        let citees = Set(citations.keys.map(\.key))
        for fiche in fiches where !citees.contains(fiche.key) {
            guard let handle = PersonHandle(name: fiche.name) else { continue }
            lignes.append(Ligne(handle: handle, compte: 0, derniere: nil, aUneNote: true))
        }
        return lignes.sorted { gauche, droite in
            switch (gauche.derniere, droite.derniere) {
            case let (g?, d?) where g.raw != d.raw: g.raw > d.raw
            case (nil, _?): false
            case (_?, nil): true
            default: gauche.handle < droite.handle
            }
        }
    }
}
