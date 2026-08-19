import Foundation

/// Ce qui était prévu, face à ce qui a été fait.
///
/// Le rapprochement est automatique et sans réglage : rien à cocher le soir,
/// sinon on ne le coche pas. Une sortie enregistrée le jour d'une séance
/// prévue, dans le même sport, accomplit cette séance — c'est la règle
/// entière, et elle se trompe rarement pour un plan personnel où l'on ne fait
/// pas deux fois le même sport par accident.
///
/// Pure, hors de toute vue et de tout magasin : c'est la seule partie de
/// l'écran d'entraînement qui puisse se tromper en silence, donc la seule qui
/// mérite d'être vérifiée à part.
enum TrainingMatch {
    /// Les sports qui s'accomplissent l'un l'autre.
    ///
    /// Un plan dit « sortie longue en trail » et la montre enregistre une
    /// course sur route parce que le parcours a changé la veille : la séance
    /// est faite. Exiger l'égalité stricte aurait laissé la moitié d'un plan
    /// en souffrance pour une nuance que le plan ne portait pas.
    ///
    /// Les familles, et pas un « tout vaut tout » : une natation ne remplace
    /// pas un footing, et l'afficher accomplie serait un mensonge confortable.
    static let familles: [Set<SportType>] = [
        [.ride, .mountainBikeRide, .gravelRide, .eBikeRide],
        [.run, .trailRun],
        [.walk, .hike],
        [.nordicSki, .alpineSki],
    ]

    private static func memeFamille(_ un: SportType, _ autre: SportType) -> Bool {
        un == autre || familles.contains { $0.contains(un) && $0.contains(autre) }
    }

    /// Une séance et, s'il y en a une, la sortie qui l'a accomplie.
    struct Paire<Seance, Sortie> {
        var seance: Seance
        var sortie: Sortie?
    }

    struct Resultat<Seance, Sortie> {
        /// Les séances du jour, dans leur ordre, chacune avec sa sortie ou sans.
        var paires: [Paire<Seance, Sortie>]
        /// Ce qui a été fait sans avoir été prévu — une sortie improvisée, un
        /// jour de repos où l'on est quand même sorti. Montré, jamais caché :
        /// c'est de l'entraînement même s'il n'était pas au programme.
        var enPlus: [Sortie]
    }

    /// Apparie les séances d'**un** jour avec les sorties de ce jour.
    ///
    /// Deux passes : d'abord le sport exact, ensuite la famille. L'ordre
    /// compte — sans la première passe, un plan « footing puis vélo » un jour
    /// où l'on a fait les deux pourrait donner le vélo au footing si le vélo
    /// arrivait en premier dans la liste.
    static func apparie<Seance, Sortie>(
        seances: [Seance], sorties: [Sortie],
        sportSeance: (Seance) -> SportType, sportSortie: (Sortie) -> SportType
    ) -> Resultat<Seance, Sortie> {
        var libres = Array(sorties.indices)
        var attribuee = [Int?](repeating: nil, count: seances.count)

        for exact in [true, false] {
            for (rang, seance) in seances.enumerated() where attribuee[rang] == nil {
                let vise = sportSeance(seance)
                guard let place = libres.firstIndex(where: { index in
                    let fait = sportSortie(sorties[index])
                    return exact ? fait == vise : memeFamille(vise, fait)
                }) else { continue }
                attribuee[rang] = libres.remove(at: place)
            }
        }

        return Resultat(
            paires: seances.enumerated().map { rang, seance in
                Paire(seance: seance, sortie: attribuee[rang].map { sorties[$0] })
            },
            enPlus: libres.map { sorties[$0] }
        )
    }
}
