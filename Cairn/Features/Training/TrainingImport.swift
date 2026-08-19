import Foundation

/// Lire une ligne de plan écrite à la main.
///
/// Le plan vient d'un calendrier macOS où chaque séance est un événement dont
/// tout tient dans le titre : « Footing 45' », « SL 18 km D+600 »,
/// « Natation 2000 m ». Personne n'a rempli de champs — il n'y en avait pas —
/// donc l'import doit lire ce que la main a écrit.
///
/// Volontairement modeste : ce qu'elle ne reconnaît pas reste dans le titre,
/// que l'écran affiche tel quel. Une devinette ratée coûte une correction ;
/// un titre effacé au profit d'une devinette coûte l'information.
enum TrainingImport {
    /// Ce qu'une ligne de calendrier devient.
    struct Lu: Equatable {
        var sport: SportType
        var titre: String
        var distance: Double?
        var duree: Double?
        var denivele: Double?
    }

    /// Les mots par lesquels un plan nomme ses sports, en français et en
    /// abrégé, du plus précis au plus général.
    ///
    /// L'ordre compte : « trail » avant « course », sans quoi une sortie
    /// trail contenant le mot « course » tomberait sur la route.
    private static let motsParSport: [(SportType, [String])] = [
        (.trailRun, ["trail", "sentier", "montagne"]),
        (.run, ["footing", "course", "run", "fractionné", "fractionne", "seuil",
                "sortie longue", "sl ", "cap ", "endurance", "jogging", "vma"]),
        (.mountainBikeRide, ["vtt", "mtb"]),
        (.gravelRide, ["gravel"]),
        (.eBikeRide, ["vae", "vélo électrique", "velo electrique"]),
        (.ride, ["vélo", "velo", "bike", "home-trainer", "home trainer", "ht ",
                 "cyclisme", "route"]),
        (.swim, ["natation", "nage", "bassin", "piscine", "swim", "crawl"]),
        (.hike, ["rando", "randonnée", "randonnee"]),
        (.walk, ["marche"]),
        (.nordicSki, ["ski de fond", "skating", "fond"]),
        (.alpineSki, ["ski alpin", "ski de rando", "ski"]),
        (.rowing, ["aviron", "rameur"]),
        (.workout, ["renfo", "renforcement", "muscu", "gainage", "ppg", "yoga",
                    "étirements", "etirements", "mobilité", "mobilite"]),
    ]

    static func sport(depuis texte: String) -> SportType {
        let minuscule = " " + texte.lowercased() + " "
        for (sport, mots) in motsParSport where mots.contains(where: { minuscule.contains($0) }) {
            return sport
        }
        return .other
    }

    /// « 18 km », « 18,5km », « 2000 m » — en mètres.
    ///
    /// Les mètres ne comptent que par milliers : « 400 m » dans un titre de
    /// course est un fractionné, pas une sortie de quatre cents mètres, et le
    /// lire comme une distance aurait rempli les plans de sorties absurdes.
    /// Une natation, elle, se dit bien en mètres — d'où le seuil plutôt qu'un
    /// refus pur et simple.
    static func distance(depuis texte: String) -> Double? {
        if let km = premierNombre(dans: texte, unite: #"k(?:m|ms)?"#) { return km * 1000 }
        if let metres = premierNombre(dans: texte, unite: "m"), metres >= 1000 { return metres }
        return nil
    }

    /// « 1h30 », « 1 h », « 45' », « 45 min » — en secondes.
    static func duree(depuis texte: String) -> Double? {
        let bas = texte.lowercased()
        if let (heures, minutes) = capture(
            #"(\d{1,2})\s*h\s*(\d{1,2})?"#, dans: bas
        ) {
            return heures * 3600 + (minutes ?? 0) * 60
        }
        if let minutes = premierNombre(dans: bas, unite: #"(?:min(?:ute)?s?|mn|')"#) {
            return minutes * 60
        }
        return nil
    }

    /// « D+600 », « d+ 600m », « 600 D+ ».
    static func denivele(depuis texte: String) -> Double? {
        let bas = texte.lowercased()
        if let (valeur, _) = capture(#"d\s*\+\s*(\d{2,5})"#, dans: bas) { return valeur }
        if let (valeur, _) = capture(#"(\d{2,5})\s*m?\s*d\s*\+"#, dans: bas) { return valeur }
        return nil
    }

    /// Une ligne entière, lue d'un coup.
    static func lire(_ texte: String) -> Lu {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        return Lu(
            sport: sport(depuis: propre),
            titre: propre,
            distance: distance(depuis: propre),
            duree: duree(depuis: propre),
            denivele: denivele(depuis: propre)
        )
    }

    // MARK: - Lecture des nombres

    private static func premierNombre(dans texte: String, unite: String) -> Double? {
        // La borne derrière l'unité empêche « 18 km » de se lire dans
        // « 18 kmh ». Une négation de lettre ou de chiffre, et non `\b` :
        // l'apostrophe de « 45' » n'est pas un caractère de mot, donc `\b` n'y
        // voyait aucune frontière et la minute se perdait — mesuré.
        //
        // Le point ou la virgule décimale sont acceptés, un plan s'écrivant
        // aussi bien « 18,5 km » que « 18.5 km ».
        capture(
            #"(\d+(?:[.,]\d+)?)\s*"# + unite + #"(?![\p{L}\p{N}])"#,
            dans: texte.lowercased()
        )?.0
    }

    /// Les un ou deux nombres capturés par un motif, virgule décimale comprise.
    private static func capture(_ motif: String, dans texte: String) -> (Double, Double?)? {
        guard let regex = try? NSRegularExpression(pattern: motif),
              let trouve = regex.firstMatch(
                in: texte, range: NSRange(texte.startIndex..., in: texte)
              )
        else { return nil }

        func nombre(_ index: Int) -> Double? {
            guard index < trouve.numberOfRanges,
                  let plage = Range(trouve.range(at: index), in: texte)
            else { return nil }
            return Double(texte[plage].replacingOccurrences(of: ",", with: "."))
        }
        guard let premier = nombre(1) else { return nil }
        return (premier, nombre(2))
    }
}
