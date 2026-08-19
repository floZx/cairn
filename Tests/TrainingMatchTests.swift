import Testing
@testable import Cairn

@Suite("Rapprochement séance et sortie")
struct TrainingMatchTests {
    /// Des paires minces : le rapprochement ne connaît que des sports, et
    /// l'éprouver sur des `@Model` demanderait un magasin pour rien.
    private struct Seance { let sport: SportType }
    private struct Sortie { let sport: SportType; let nom: String }

    private func apparie(
        _ seances: [SportType], _ sorties: [(SportType, String)]
    ) -> TrainingMatch.Resultat<Seance, Sortie> {
        TrainingMatch.apparie(
            seances: seances.map(Seance.init),
            sorties: sorties.map { Sortie(sport: $0.0, nom: $0.1) },
            sportSeance: \.sport, sportSortie: \.sport
        )
    }

    @Test func uneSortieDuMemeSportAccomplitLaSeance() {
        let resultat = apparie([.run], [(.run, "Footing")])
        #expect(resultat.paires.first?.sortie?.nom == "Footing")
        #expect(resultat.enPlus.isEmpty)
    }

    @Test func unSportEtrangerNAccomplitRien() {
        let resultat = apparie([.run], [(.swim, "Bassin")])
        #expect(resultat.paires.first?.sortie == nil)
        #expect(resultat.enPlus.map(\.nom) == ["Bassin"])
    }

    @Test func leTrailAccomplitLaCourse() {
        let resultat = apparie([.trailRun], [(.run, "Sur route finalement")])
        #expect(resultat.paires.first?.sortie?.nom == "Sur route finalement")
    }

    /// Le sport exact passe avant la famille, et c'est tout l'intérêt des
    /// deux passes : sans elles, le trail rangé en premier aurait pris la
    /// course sur route et laissé la séance de course avec le trail.
    @Test func leSportExactPasseAvantLaFamille() {
        let resultat = apparie(
            [.trailRun, .run], [(.run, "Route"), (.trailRun, "Sentier")]
        )
        #expect(resultat.paires.map(\.sortie?.nom) == ["Sentier", "Route"])
    }

    @Test func uneSortieNonPrevueResteVisible() {
        let resultat = apparie([.run], [(.run, "Footing"), (.ride, "Vélo du soir")])
        #expect(resultat.paires.first?.sortie?.nom == "Footing")
        #expect(resultat.enPlus.map(\.nom) == ["Vélo du soir"])
    }

    /// Deux séances du même sport, une seule faite : la première est servie,
    /// la seconde reste en attente plutôt que les deux à moitié.
    @Test func uneSeuleSortiePourDeuxSeances() {
        let resultat = apparie([.swim, .swim], [(.swim, "Bassin")])
        #expect(resultat.paires.map(\.sortie?.nom) == ["Bassin", nil])
    }

    @Test func unJourSansRienNeCasseRien() {
        let resultat = apparie([], [])
        #expect(resultat.paires.isEmpty)
        #expect(resultat.enPlus.isEmpty)
    }

    /// La natation ne remplace pas le footing, et le vélo non plus.
    @Test func lesFamillesNeSeMelangentPas() {
        let resultat = apparie([.run], [(.ride, "Home-trainer")])
        #expect(resultat.paires.first?.sortie == nil)
    }
}
