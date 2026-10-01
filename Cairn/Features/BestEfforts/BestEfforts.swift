import Foundation

/// Les distances des meilleurs efforts, celles de Strava : de 400 m au
/// marathon, miles compris — on lit encore ses temps au mile.
///
/// L'ordre des cas est celui de l'affichage, du plus court au plus long.
enum EffortDistance: Int, CaseIterable, Identifiable, Sendable, Codable {
    case m400, halfMile, km1, mile, twoMiles, km5, km10, km15, tenMiles, km20, halfMarathon, km30, marathon

    var id: Int { rawValue }

    var metres: Double {
        switch self {
        case .m400: 400
        case .halfMile: 804.672
        case .km1: 1000
        case .mile: 1609.344
        case .twoMiles: 3218.688
        case .km5: 5000
        case .km10: 10_000
        case .km15: 15_000
        case .tenMiles: 16_093.44
        case .km20: 20_000
        case .halfMarathon: 21_097.5
        case .km30: 30_000
        case .marathon: 42_195
        }
    }

    var label: String {
        switch self {
        case .m400: "400 m"
        case .halfMile: "1/2 mile"
        case .km1: "1 km"
        case .mile: "1 mile"
        case .twoMiles: "2 miles"
        case .km5: "5 km"
        case .km10: "10 km"
        case .km15: "15 km"
        case .tenMiles: "10 miles"
        case .km20: "20 km"
        case .halfMarathon: "Semi-marathon"
        case .km30: "30 km"
        case .marathon: "Marathon"
        }
    }
}

/// Le calcul des meilleurs efforts d'une sortie, à partir de ses séries
/// distance et temps — les mêmes pour une sortie Strava, un GPX importé ou
/// une montre : le journal est la référence, pas le service qui l'alimente.
///
/// Calculé ici plutôt que repris de Strava : son API ne rend les
/// `best_efforts` que sur le détail d'une activité, une requête par sortie, et
/// rien pour un fichier importé.
enum BestEfforts {
    /// À pied et en courant. La marche et la randonnée n'ont pas de record au
    /// 400 m qui vaille, et un vélo en aurait trop.
    static let sports: Set<SportType> = [.run, .trailRun]

    /// Au-delà, c'est le GPS qui a sauté, pas le coureur : 8,5 m/s, c'est un
    /// 400 m en 47 s.
    static let maximumSpeed: Double = 8.5

    /// Les classements retenus : or, argent, bronze.
    static let podium = 3

    /// Les efforts d'une sortie enregistrée, depuis la meilleure distance
    /// cumulée qu'elle porte.
    ///
    /// Dans l'ordre : la série `distance` de la montre, celle que Strava
    /// utilise ; à défaut, la vitesse lissée intégrée seconde par seconde ; à
    /// défaut encore, la trace GPS. Une bonne part de la bibliothèque n'a pas
    /// de série `distance` — 446 sorties à pied sur 521 le 1er octobre 2026 —
    /// et c'est par là que le 10 km du 28 juin manquait au classement. La
    /// vitesse intégrée retombe sur les temps de Strava à la seconde près
    /// (28 juin : 97 s au 400 m pour 97, 2 659 s au 10 km pour 2 659) ; la
    /// trace GPS, plus bruitée, allonge la distance et flatte les temps.
    static func compute(streams: ActivityStreams) -> [EffortDistance: Double] {
        guard let timeBlob = streams.time else { return [:] }
        let time = TrackBlob.decodeTimes(timeBlob)
        guard time.count > 1 else { return [:] }
        if let blob = streams.distance {
            let distance = TrackBlob.decodeScalars(blob).map(Double.init)
            if distance.count == time.count { return compute(distance: distance, time: time) }
        }
        if let blob = streams.velocitySmooth {
            let velocity = TrackBlob.decodeScalars(blob)
            if velocity.count == time.count {
                return compute(distance: integrate(velocity: velocity, time: time), time: time)
            }
        }
        let coordinates = streams.coordinates
        if coordinates.count == time.count {
            return compute(distance: accumulate(coordinates), time: time)
        }
        return [:]
    }

    /// La distance cumulée qu'une vitesse fait parcourir.
    static func integrate(velocity: [Float], time: [Int32]) -> [Double] {
        var distance = [Double](repeating: 0, count: velocity.count)
        for index in velocity.indices.dropFirst() {
            let elapsed = Double(time[index] - time[index - 1])
            distance[index] = distance[index - 1] + Double(velocity[index]) * max(elapsed, 0)
        }
        return distance
    }

    /// La distance cumulée le long d'une trace.
    static func accumulate(_ coordinates: [Coordinate]) -> [Double] {
        var distance = [Double](repeating: 0, count: coordinates.count)
        for index in coordinates.indices.dropFirst() {
            distance[index] = distance[index - 1]
                + TrackMetrics.distance(of: [coordinates[index - 1], coordinates[index]])
        }
        return distance
    }

    /// Le meilleur temps, en secondes, pour chaque distance que la sortie
    /// couvre.
    ///
    /// Une fenêtre glissante sur la distance cumulée : pour chaque point
    /// d'arrivée, le départ le plus tardif qui laisse encore la distance
    /// entière derrière lui. Sans interpolation, comme Strava : la fenêtre
    /// part et finit sur des points mesurés, quitte à couvrir quelques mètres
    /// de plus. Interpoler donnait une seconde de mieux que Strava sur un
    /// 400 m sur deux — vérifié sur les sorties du 28 juin et du 1er octobre.
    ///
    /// Le temps est celui de la montre, pauses comprises, comme Strava : un
    /// arrêt au feu coûte au record.
    static func compute(distance rawDistance: [Double], time: [Int32]) -> [EffortDistance: Double] {
        let count = min(rawDistance.count, time.count)
        guard count > 1 else { return [:] }

        // Cumulée, donc croissante : un recul (rare, mais un GPS recalé en
        // produit) est aplati plutôt que d'ouvrir une fenêtre impossible.
        var distance = [Double](repeating: 0, count: count)
        var highest = rawDistance[0]
        for index in 0..<count {
            highest = max(highest, rawDistance[index])
            distance[index] = highest
        }
        let total = distance[count - 1] - distance[0]

        var result: [EffortDistance: Double] = [:]
        for target in EffortDistance.allCases where target.metres <= total {
            var best = Int32.max
            var start = 0
            for end in 1..<count {
                while start + 1 < end, distance[end] - distance[start + 1] >= target.metres {
                    start += 1
                }
                guard distance[end] - distance[start] >= target.metres else { continue }
                let elapsed = time[end] - time[start]
                if elapsed > 0 { best = min(best, elapsed) }
            }
            if best < .max, target.metres / Double(best) <= maximumSpeed {
                result[target] = Double(best)
            }
        }
        return result
    }
}

extension BestEfforts {
    /// Ce qu'`Activity.bestEfforts` garde : une case par distance, dans
    /// l'ordre de `EffortDistance`, 0 où la sortie ne va pas. Nil quand elle
    /// ne couvre même pas 400 m.
    static func encode(_ times: [EffortDistance: Double]) -> [Double]? {
        guard !times.isEmpty else { return nil }
        return EffortDistance.allCases.map { times[$0] ?? 0 }
    }
}

/// Une sortie et ses meilleurs efforts, tels qu'un classement les lit.
struct ActivityEfforts: Sendable, Equatable {
    let uuid: String
    let date: Date
    let times: [EffortDistance: Double]
}

/// Une place sur un podium : quelle distance, quel rang, quel temps.
struct EffortMedal: Sendable, Equatable, Hashable {
    let distance: EffortDistance
    /// 1, 2 ou 3.
    let rank: Int
    let seconds: Double
}

/// Les classements, distance par distance.
struct EffortStandings: Sendable, Equatable {
    struct Entry: Sendable, Equatable, Identifiable {
        let uuid: String
        let date: Date
        let seconds: Double
        var id: String { uuid }
    }

    /// Du plus rapide au plus lent ; à égalité, le plus ancien d'abord — il
    /// l'a couru le premier.
    let byDistance: [EffortDistance: [Entry]]

    init(_ efforts: some Sequence<ActivityEfforts>) {
        var grouped: [EffortDistance: [Entry]] = [:]
        for activity in efforts {
            for (distance, seconds) in activity.times {
                grouped[distance, default: []].append(
                    Entry(uuid: activity.uuid, date: activity.date, seconds: seconds)
                )
            }
        }
        byDistance = grouped.mapValues { entries in
            entries.sorted {
                $0.seconds != $1.seconds ? $0.seconds < $1.seconds : $0.date < $1.date
            }
        }
    }

    func top(_ distance: EffortDistance, _ count: Int = BestEfforts.podium) -> [Entry] {
        Array((byDistance[distance] ?? []).prefix(count))
    }

    /// Les podiums de chaque sortie, la distance la plus courte d'abord.
    func medals() -> [String: [EffortMedal]] {
        var medals: [String: [EffortMedal]] = [:]
        for distance in EffortDistance.allCases {
            for (index, entry) in top(distance).enumerated() {
                medals[entry.uuid, default: []].append(
                    EffortMedal(distance: distance, rank: index + 1, seconds: entry.seconds)
                )
            }
        }
        return medals
    }
}

extension Format {
    /// Un temps de course : « 21:34 », « 1:42:07 ». Les heures seulement
    /// quand il y en a — un 5 km écrit « 0:21:34 » se lit moins vite.
    static func raceTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// « 1er », « 2e », « 3e ».
    static func rank(_ rank: Int) -> String {
        rank == 1 ? "1er" : "\(rank)e"
    }
}
