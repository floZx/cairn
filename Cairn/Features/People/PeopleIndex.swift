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

        var libelle: String {
            switch self {
            case .journal: "Journal"
            case .sortie(let nom): nom
            case .repas(let creneau): creneau
            case .pesee: "Pesée"
            }
        }
    }

    /// Un texte qui cite quelqu'un.
    struct Citation: Identifiable, Equatable {
        var dateKey: DateKey
        var source: Source
        /// Ce qu'on montre : les seuls passages où elle est nommée, pas la note
        /// entière. Voir `extrait(de:citant:)`.
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

    /// Qui est qui : chaque nom cité, par sa clé, vers la personne qu'il
    /// désigne.
    ///
    /// Tiré des fiches : les alias d'une fiche mènent à son nom, et son nom à
    /// lui-même — si bien qu'une mention écrite « @christele » s'affiche sous
    /// l'orthographe de la fiche. Un alias qui serait le nom d'une autre fiche
    /// est ignoré : cette personne-là existe, et le lien ne va que dans un
    /// sens. Pas de chaîne non plus — l'alias d'un alias ne mène nulle part.
    struct Annuaire: Equatable {
        private(set) var parCle: [String: PersonHandle] = [:]
        /// Les alias retenus de chaque fiche, par la clé de son nom, tels
        /// qu'écrits.
        private(set) var aliasParPrincipal: [String: [PersonHandle]] = [:]

        static let vide = Annuaire()

        init() {}

        init(fiches: [(name: String, aliases: [String])]) {
            let principaux = fiches.compactMap { PersonHandle(name: $0.name) }
            let nomsPropres = Set(principaux.map(\.key))
            for principal in principaux { parCle[principal.key] = principal }
            for fiche in fiches {
                guard let principal = PersonHandle(name: fiche.name) else { continue }
                for alias in fiche.aliases {
                    guard let handle = PersonHandle(name: alias),
                          !nomsPropres.contains(handle.key),
                          parCle[handle.key] == nil
                    else { continue }
                    parCle[handle.key] = principal
                    aliasParPrincipal[principal.key, default: []].append(handle)
                }
            }
        }

        /// La personne qu'un nom cité désigne — lui-même quand il n'est
        /// l'alias de personne.
        func resoudre(_ handle: PersonHandle) -> PersonHandle {
            parCle[handle.key] ?? handle
        }

        /// Les alias de quelqu'un, pour les lui montrer et les proposer.
        func alias(de principal: PersonHandle) -> [PersonHandle] {
            aliasParPrincipal[principal.key] ?? []
        }
    }

    /// Les citations de chacun, les plus récentes d'abord.
    ///
    /// Une personne citée deux fois dans le même texte n'y figure qu'une : on
    /// veut la liste des notes qui parlent d'elle, pas celle des occurrences.
    /// Sous un alias comme sous son nom, c'est la même personne, et la même
    /// règle.
    static func citations(
        dans textes: [Texte], annuaire: Annuaire = .vide
    ) -> [PersonHandle: [Citation]] {
        var index: [PersonHandle: [Citation]] = [:]
        for texte in textes {
            let propre = texte.contenu.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !propre.isEmpty else { continue }
            let citees = Set(PersonScanner.mentions(in: propre).map(annuaire.resoudre))
            for handle in citees {
                index[handle, default: []].append(
                    Citation(
                        dateKey: texte.dateKey, source: texte.source,
                        texte: extrait(de: propre, citant: handle, annuaire: annuaire),
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

    /// Ce qu'on montre d'un texte sur la fiche de quelqu'un : les passages où
    /// elle est nommée, et rien d'autre.
    ///
    /// Une note de journée raconte la journée entière — le réveil, la sortie,
    /// le dîner. La fiche d'une personne recopiait tout cela parce que son nom
    /// apparaissait une fois au milieu, si bien que dix citations faisaient dix
    /// notes à relire pour retrouver la phrase qui parle d'elle.
    ///
    /// Plusieurs passages citants sont recollés, séparés par une ligne vide :
    /// une citation reste une note, comme le dit `citations(dans:)`, elle est
    /// seulement réduite à ce qui la concerne. Et le texte entier quand le
    /// découpage ne trouve rien — mieux vaut trop montrer que rien.
    static func extrait(
        de texte: String, citant handle: PersonHandle, annuaire: Annuaire = .vide
    ) -> String {
        let citants = unites(de: texte).filter {
            PersonScanner.mentions(in: $0).map(annuaire.resoudre).contains(handle)
        }
        return citants.isEmpty ? texte : citants.joined(separator: "\n\n")
    }

    /// Les unités de lecture d'un texte : les blocs séparés par une ligne
    /// vide, et **chaque item de liste** pour son compte.
    ///
    /// Les items comptent à part parce qu'une note de journée en est souvent
    /// faite de bout en bout. Sans cela, « le paragraphe » d'une liste de dix
    /// lignes est la note entière, et on n'aurait rien découpé.
    ///
    /// Une ligne ordinaire, elle, prolonge ce qui précède : un paragraphe
    /// replié sur trois lignes reste un paragraphe, et l'extrait ne doit pas
    /// s'arrêter au milieu d'une phrase.
    static func unites(de texte: String) -> [String] {
        var unites: [String] = []
        var courante: [String] = []
        func clore() {
            if !courante.isEmpty { unites.append(courante.joined(separator: "\n")) }
            courante = []
        }
        for ligne in texte.components(separatedBy: CharacterSet.newlines) {
            if ligne.trimmingCharacters(in: .whitespaces).isEmpty {
                clore()
                continue
            }
            if !courante.isEmpty, ouvreUneUnite(ligne) { clore() }
            courante.append(ligne)
        }
        clore()
        return unites
    }

    /// Ce qui ouvre une unité au milieu d'un bloc : un item de liste — `-`,
    /// `*`, `+`, `1.`, `1)` — ou un titre.
    ///
    /// L'espace après la puce est exigé, sinon un trait de séparation `---` ou
    /// une phrase commençant par un tiret cadratin ouvrirait une unité.
    /// L'indentation est ignorée : un sous-item est un item.
    private static func ouvreUneUnite(_ ligne: String) -> Bool {
        let nu = ligne.drop { $0 == " " || $0 == "\t" }
        if nu.hasPrefix("#") { return true }
        if let premier = nu.first, "-*+".contains(premier) {
            return nu.dropFirst().first == " "
        }
        let chiffres = nu.prefix(while: \.isNumber)
        guard !chiffres.isEmpty else { return false }
        let suite = nu.dropFirst(chiffres.count)
        guard let ponctuation = suite.first, ponctuation == "." || ponctuation == ")" else {
            return false
        }
        return suite.dropFirst().first == " "
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

    /// Les ordres que la liste des gens propose.
    enum Tri: String, CaseIterable, Identifiable, Sendable {
        /// La plus récemment citée d'abord — l'ordre de toujours.
        case recentes
        case alphabetique
        /// La plus citée d'abord.
        case nombre

        static let storageKey = "peopleSort"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .recentes: "Récentes"
            case .alphabetique: "Alphabétique"
            case .nombre: "Nombre de notes"
            }
        }
    }

    /// La liste remise dans un autre ordre.
    ///
    /// À égalité — même nombre de notes —, l'ordre alphabétique départage :
    /// une liste qui change d'ordre d'une ouverture à l'autre pour deux
    /// personnes ex æquo ferait douter du tri lui-même.
    static func trier(_ lignes: [Ligne], par tri: Tri) -> [Ligne] {
        switch tri {
        case .recentes:
            return lignes
        case .alphabetique:
            return lignes.sorted { $0.handle < $1.handle }
        case .nombre:
            return lignes.sorted {
                $0.compte != $1.compte ? $0.compte > $1.compte : $0.handle < $1.handle
            }
        }
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

extension PeopleIndex.Annuaire {
    /// L'annuaire tiré des fiches du magasin.
    init(people: [Person]) {
        self.init(fiches: people.map { (name: $0.name, aliases: $0.aliases) })
    }
}
