import Testing
@testable import Cairn

@Suite("Déduire le type de journée depuis le plan")
struct TrainingDayTypeRuleTests {
    private typealias Seance = TrainingDayTypeRule.Seance

    private func categorie(_ seances: [Seance]) -> TrainingDayTypeRule.Categorie? {
        TrainingDayTypeRule.categorie(pour: seances)
    }

    @Test func unJourSansSeanceEstDuRepos() {
        #expect(categorie([]) == .repos)
    }

    @Test func leRenfoSeulEstLeger() {
        #expect(categorie([Seance(sport: .workout, titre: "Renfo 30 min")]) == .leger)
    }

    @Test("un footing ou une natation seuls", arguments: [SportType.run, .trailRun, .swim])
    func uneSeanceSimple(_ sport: SportType) {
        #expect(categorie([Seance(sport: sport, titre: "Footing facile")]) == .footingOuNatation)
    }

    @Test("les mots de la qualité", arguments: [
        "Côtes 6x45''", "Fractionné court", "Seuil 3x2000", "VMA courte",
        "Tempo 20 min", "4 × 1000 à allure",
    ])
    func laQualiteSeReconnait(_ titre: String) {
        #expect(categorie([Seance(sport: .run, titre: titre)]) == .qualite)
    }

    @Test("la sortie longue, par le mot ou par la durée", arguments: [
        ("SL 18 km", nil as Double?),
        ("Sortie longue vallonnée", nil),
        ("Footing", 95 * 60),
    ])
    func laSortieLongueSeReconnait(_ titre: String, _ duree: Double?) {
        #expect(categorie([Seance(sport: .run, titre: titre, duree: duree)]) == .sortieLongue)
    }

    /// « slalom » n'est pas « SL » : le mot entier, pas la suite de lettres.
    @Test func slNEstPasUnMorceauDeMot() {
        #expect(categorie([Seance(sport: .alpineSki, titre: "Slalom")]) != .sortieLongue)
    }

    @Test func courseEtNatationLeMemeJour() {
        #expect(categorie([
            Seance(sport: .run, titre: "Footing"),
            Seance(sport: .swim, titre: "Natation 2000 m"),
        ]) == .deuxSeances)
    }

    /// Deux footings, c'est deux fois la même chose, pas deux disciplines.
    @Test func deuxFootingsNeFontPasUneJourneeDouble() {
        #expect(categorie([
            Seance(sport: .run, titre: "Footing matin"),
            Seance(sport: .run, titre: "Footing soir"),
        ]) != .deuxSeances)
    }

    /// L'ordre des cas **est** la règle : le budget le plus haut l'emporte.
    @Test func laSortieLonguePasseAvantLaQualite() {
        #expect(categorie([
            Seance(sport: .run, titre: "SL 25 km avec 3x2000 au seuil")
        ]) == .sortieLongue)
    }

    @Test func laDoubleSeancePasseAvantLaQualite() {
        #expect(categorie([
            Seance(sport: .run, titre: "Côtes 6x45''"),
            Seance(sport: .swim, titre: "Natation"),
        ]) == .deuxSeances)
    }

    /// Ce qu'aucun cas ne couvre reste sans type, plutôt que de recevoir le
    /// moins mauvais.
    @Test func unVeloSeulNeSeDeduitPas() {
        #expect(categorie([Seance(sport: .ride, titre: "Home-trainer 1h")]) == nil)
    }

    // MARK: - Le rapprochement par nom

    private struct Journee { let nom: String }

    @Test("les six noms se retrouvent, accents et casse compris", arguments: [
        (TrainingDayTypeRule.Categorie.repos, "Repos"),
        (.leger, "Renfo/Léger"),
        (.footingOuNatation, "Footing ou natation"),
        (.qualite, "Qualité"),
        (.deuxSeances, "Footing + natation"),
        (.sortieLongue, "Sortie longue"),
    ])
    func leNomSeRetrouve(_ categorie: TrainingDayTypeRule.Categorie, _ nom: String) {
        let trouve = TrainingDayTypeRule.type(categorie, parmi: [Journee(nom: nom)], nom: \.nom)
        #expect(trouve?.nom == nom)
    }

    /// Renommer un type le débranche de la règle plutôt que de lui faire dire
    /// autre chose.
    @Test func unTypeRenommeNEstPlusRattache() {
        let types = [Journee(nom: "Journée tranquille")]
        #expect(TrainingDayTypeRule.type(.repos, parmi: types, nom: \.nom) == nil)
    }
}
