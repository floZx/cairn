import Foundation

/// Déduire le type de journée nutrition à partir de ce qui est prévu.
///
/// Le plan vient d'un calendrier dont les événements ne portent aucun type :
/// il aurait fallu rouvrir chaque journée pour poser un budget. Or les six
/// types définis se lisent presque tous dans le plan — c'est le tableau validé
/// le 19 août 2026, et c'est lui qui décide ici, pas l'inverse.
///
/// La règle ne devine que ce qu'elle sait : une journée qu'aucun cas ne couvre
/// reste sans type plutôt que de recevoir le moins mauvais.
enum TrainingDayTypeRule {
    /// Ce qu'une journée de plan est, du point de vue du budget.
    enum Categorie: CaseIterable {
        case repos
        case leger
        case footingOuNatation
        case qualite
        case deuxSeances
        case sortieLongue

        /// Le nom du type de journée qui lui correspond, tel qu'il est écrit
        /// dans les réglages.
        ///
        /// Rapproché par le nom et non par un identifiant : les types sont des
        /// lignes qu'on crée soi-même, et rien ne les marque comme « la
        /// journée de repos ». Conséquence assumée — renommer un type le
        /// débranche de la règle plutôt que de lui faire dire autre chose, et
        /// l'aperçu le montre avant d'écrire.
        var nomCanonique: String {
            switch self {
            case .repos: "repos"
            case .leger: "renfo/leger"
            case .footingOuNatation: "footing ou natation"
            case .qualite: "qualite"
            case .deuxSeances: "footing + natation"
            case .sortieLongue: "sortie longue"
            }
        }
    }

    /// Une séance, réduite à ce dont la règle a besoin.
    struct Seance {
        var sport: SportType
        var titre: String
        var duree: Double?
        var distance: Double?

        init(sport: SportType, titre: String, duree: Double? = nil, distance: Double? = nil) {
            self.sport = sport
            self.titre = titre
            self.duree = duree
            self.distance = distance
        }
    }

    /// Les mots par lesquels un plan nomme une séance de qualité.
    private static let motsDeQualite = [
        "côte", "cote", "fractionn", "seuil", "vma", "tempo", "allure spécifique",
        "allure specifique", "intervalle",
    ]

    /// Une heure et demie : au-delà, une séance n'est plus un footing quel que
    /// soit le mot employé pour la nommer.
    private static let seuilLong: Double = 90 * 60

    static func categorie(pour seances: [Seance]) -> Categorie? {
        // L'ordre des cas est la règle elle-même, et il se lit de haut en bas :
        // le premier qui répond gagne. Une sortie longue qui contient du seuil
        // reste une sortie longue — c'est le budget le plus haut qui doit
        // l'emporter, pas le mot le plus précis.
        if seances.isEmpty { return .repos }
        if seances.contains(where: estLongue) { return .sortieLongue }
        if deuxSeancesComplementaires(seances) { return .deuxSeances }
        if seances.contains(where: estDeQualite) { return .qualite }
        if seances.allSatisfy({ $0.sport == .workout }) { return .leger }
        if seances.count == 1, estFootingOuNatation(seances[0]) { return .footingOuNatation }
        return nil
    }

    /// Le type correspondant, s'il existe dans les réglages.
    static func type<T>(
        _ categorie: Categorie, parmi types: [T], nom: (T) -> String
    ) -> T? {
        types.first { normalise(nom($0)) == categorie.nomCanonique }
    }

    // MARK: - Les cas

    private static func estLongue(_ seance: Seance) -> Bool {
        if let duree = seance.duree, duree > seuilLong { return true }
        let titre = normalise(seance.titre)
        if titre.contains("sortie longue") { return true }
        // « SL » comme mot : « SL 18 km » oui, « slalom » non.
        return mots(titre).contains("sl")
    }

    private static func estDeQualite(_ seance: Seance) -> Bool {
        let titre = normalise(seance.titre)
        if motsDeQualite.contains(where: titre.contains) { return true }
        // « 6x45 », « 4 × 2000 » : la forme d'une série, quel que soit le mot
        // qui l'accompagne.
        return titre.range(of: #"\d+\s*[x×]\s*\d"#, options: .regularExpression) != nil
    }

    /// Deux séances qui se complètent — la course et le bassin du même jour.
    ///
    /// Deux footings ne comptent pas : ce type-là dit « deux disciplines »,
    /// pas « deux fois ».
    private static func deuxSeancesComplementaires(_ seances: [Seance]) -> Bool {
        guard seances.count >= 2 else { return false }
        let sports = Set(seances.map(\.sport))
        return sports.contains(.swim) && !sports.intersection([.run, .trailRun]).isEmpty
    }

    private static func estFootingOuNatation(_ seance: Seance) -> Bool {
        [.run, .trailRun, .swim].contains(seance.sport)
    }

    // MARK: - Comparaison des noms

    /// Minuscules, sans accents, espaces resserrés : « Renfo/Léger » et
    /// « renfo/leger » sont le même type, et personne ne devrait avoir à le
    /// savoir.
    static func normalise(_ texte: String) -> String {
        texte
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func mots(_ texte: String) -> Set<String> {
        Set(texte.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }
}
