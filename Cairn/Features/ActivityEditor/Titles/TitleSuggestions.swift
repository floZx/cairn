import Foundation

/// Titles written from `TitleIngredients` with plain sentence templates.
///
/// No language model: Apple's on-device one was tried on real outings and
/// gave titles that were bland at best and wrong at worst — « Boucle de
/// 180 m » for 180 m of climbing, « Course » for a ride. Templates can't be
/// wrong about the facts, so the work goes into choosing the right ones and
/// phrasing them the way a person would.
enum TitleSuggestions {
    /// Under this average, a run is an easy one. Florian's own figure: on
    /// his runs titled « EF » or « Footing » the average is 142, though a
    /// good half of them went over — heat, hills, a tired day. A title too
    /// many costs a line in a list, so the figure he runs by wins.
    static let easyHeartrate: Double = 145

    /// Five or six titles, the most telling first: the session read in the
    /// laps, then what was special about the day, then the way, the moment,
    /// the figures.
    static func make(_ i: TitleIngredients, avoiding current: String = "") -> [String] {
        let noun = Noun(i.sport)
        let start = i.places.first
        let via = Self.via(i.places)
        var titles: [String] = []

        // The session, when the laps hold one: it is what the outing was.
        if let session = i.intervals {
            titles.append(session)
            if let start { titles.append("\(session) à \(start)") }
        }

        if i.isRace {
            titles.append(start.map { "Compétition à \($0)" } ?? "\(noun.text) de compétition")
        }

        if i.isIndoor {
            switch i.sport {
            case .ride, .gravelRide, .mountainBikeRide, .eBikeRide:
                titles.append("Home-trainer du \(i.dayAndMoment)")
            case .run, .trailRun:
                titles.append("Tapis du \(i.dayAndMoment)")
            default:
                titles.append("\(noun.text) en intérieur")
            }
        }

        if i.isCommute {
            let ride: Set<SportType> = [.ride, .gravelRide, .eBikeRide]
            titles.append(
                ride.contains(i.sport)
                    ? "Vélotaf du \(i.dayAndMoment)"
                    : "Trajet du \(i.dayAndMoment)"
            )
        }

        // An easy run, said the two ways it is written: « Footing », « EF ».
        // Never over a session or a race the laps or the markers found.
        if i.sport == .run, i.intervals == nil, !i.isRace,
           let heartrate = i.averageHeartrate, heartrate > 0, heartrate < easyHeartrate {
            for word in ["Footing", "EF"] {
                if i.isIndoor {
                    titles.append("\(word) sur tapis")
                } else if let start, let via {
                    titles.append("\(word) \(start) / \(via)")
                } else if let start {
                    titles.append(word == "EF" ? "EF \(start)" : "Footing à \(start)")
                } else {
                    titles.append("\(word) du \(i.dayAndMoment)")
                }
            }
        }

        // The way: what makes an outdoor outing recognisable a year later.
        if !i.isIndoor, let start {
            titles += wayTitles(i, noun: noun, start: start, via: via)
        }

        titles.append("\(noun.text) du \(i.dayAndMoment)")

        if i.hasDistance {
            var figures = TitleIngredients.kilometres(i.distanceKm)
            if i.elevationGain >= 100 { figures += " et \(Int(i.elevationGain.rounded())) m D+" }
            titles.append(via.map { "\(figures) par \($0)" } ?? "\(noun.text) · \(figures)")
        } else if i.movingMinutes > 0 {
            titles.append("\(noun.text) · \(TitleIngredients.duration(i.movingMinutes))")
        }

        return clean(titles, avoiding: current)
    }

    private static func wayTitles(
        _ i: TitleIngredients, noun: Noun, start: String, via: String?
    ) -> [String] {
        var titles: [String] = []
        let relief = i.relief.flatMap { $0 == .flat ? nil : $0 }

        switch i.shape {
        case .loop:
            let place = via.map { "par \($0)" } ?? "autour de \(start)"
            if i.previousOnRoute >= 2 {
                titles.append("La boucle habituelle \(place)")
            }
            switch i.length {
            case .long: titles.append("Grande boucle \(place)")
            case .short: titles.append("Petite boucle \(place)")
            default: break
            }
            if let relief {
                titles.append("Boucle \(relief.adjective(feminine: true)) \(place)")
            } else {
                titles.append("Boucle \(place)")
            }
        case .outAndBack:
            titles.append("Aller-retour à \(i.places.last ?? start)")
        case .pointToPoint:
            if let end = i.places.last, end != start { titles.append("\(start) → \(end)") }
        case nil:
            break
        }

        // Sport and place together: « Trail vallonné vers Sauvain ».
        if let via {
            let adjective = relief.map { " " + $0.adjective(feminine: noun.isFeminine) } ?? ""
            titles.append("\(noun.text)\(adjective) vers \(via)")
            titles.append("\(start) / \(via)")
        } else {
            titles.append("\(noun.text) à \(start)")
        }
        return titles
    }

    /// The commune the outing is best named by, other than where it began:
    /// the middle one of those crossed — the far end of a loop, as the
    /// points are sampled in order along the way.
    static func via(_ places: [String]) -> String? {
        let beyond = Array(places.dropFirst())
        return beyond.isEmpty ? nil : beyond[beyond.count / 2]
    }

    /// Whether a title is one nobody wrote: Strava's « Course à pied le
    /// matin » and « Morning Ride », the treadmill's « Marche (tapis) », a
    /// watch's « Lyon Course à pied ». Read off a real library, where they
    /// were half of 893 activities and caught nothing typed by hand.
    ///
    /// A commune alone — « Sury-le-Comtal », « Veauchette » — isn't one:
    /// it already says where.
    static func isBanal(_ name: String) -> Bool {
        let patterns = [
            #"^(Morning|Afternoon|Evening|Night|Lunch) [A-Z][A-Za-z ]+$"#,
            // Un nom de sport seul avant le moment de la journée — minuscules
            // après la première lettre, VTT mis à part. Un nom de lieu y met
            // une majuscule : « Trail à Saint-Marcellin-en-Forez de nuit » a été
            // écrit, et le ✨ s'y proposait — signalé.
            #"^(VTT|[A-ZÀ-Ý])([\p{Ll}' -]|VTT)* (le matin|le midi|dans l'après-midi|l'après-midi|en soirée|de nuit|la nuit)$"#,
            #"^[^/]+ \(tapis\)$"#,
            #"^[A-ZÀ-Ý][\p{L}' -]+ (Course à pied|Vélo|Cyclisme|Marche|Randonnée|Natation|Trail)$"#,
            #"^(Renforcement (fonctionnel|musculaire)|Entraînement aux poids|Course à pied|Sortie vélo|Marche|Natation)$"#,
        ]
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            || patterns.contains { trimmed.range(of: $0, options: .regularExpression) != nil }
    }

    /// Trimmed, without repeats, not the title already there.
    static func clean(_ titles: [String], avoiding current: String) -> [String] {
        var seen: Set<String> = [current.lowercased().trimmingCharacters(in: .whitespaces)]
        var result: [String] = []
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return Array(result.prefix(6))
    }

    /// What the sport is called in a title, and its gender for the
    /// adjective that follows: « Course vallonnée », « Trail vallonné ».
    struct Noun {
        let text: String
        let isFeminine: Bool

        init(_ sport: SportType) {
            (text, isFeminine) = switch sport {
            case .ride: ("Vélo", false)
            case .mountainBikeRide: ("VTT", false)
            case .gravelRide: ("Gravel", false)
            case .eBikeRide: ("Vélo électrique", false)
            case .run: ("Course", true)
            case .trailRun: ("Trail", false)
            case .walk: ("Marche", true)
            case .hike: ("Rando", true)
            case .swim: ("Natation", true)
            case .nordicSki: ("Ski de fond", false)
            case .alpineSki: ("Ski", false)
            case .rowing: ("Aviron", false)
            case .workout: ("Renfo", false)
            case .other: ("Sortie", true)
            }
        }
    }
}

extension TitleIngredients.Relief {
    func adjective(feminine: Bool) -> String {
        let e = feminine ? "e" : ""
        return switch self {
        case .flat: "plat" + e
        case .rolling: "vallonné" + e
        case .hilly: "bien vallonné" + e
        case .mountain: feminine ? "montagnarde" : "montagnard"
        }
    }
}

extension TitleIngredients {
    static func kilometres(_ km: Double) -> String {
        km >= 10
            ? "\(Int(km.rounded())) km"
            : String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60
            ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
            : "\(minutes) min"
    }
}
