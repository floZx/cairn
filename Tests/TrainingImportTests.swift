import Testing
@testable import Cairn

@Suite("Lecture d'une ligne de plan")
struct TrainingImportTests {
    @Test("le sport se devine sur le mot", arguments: [
        ("Footing 45'", SportType.run),
        ("Trail 18 km", SportType.trailRun),
        ("SL 20 km", SportType.run),
        ("VTT 2h", SportType.mountainBikeRide),
        ("Vélo home-trainer 1h", SportType.ride),
        ("Natation 2000 m", SportType.swim),
        ("Renfo 30 min", SportType.workout),
        ("Repos", SportType.other),
    ])
    func leSportSeDevine(_ texte: String, _ attendu: SportType) {
        #expect(TrainingImport.sport(depuis: texte) == attendu)
    }

    /// « Trail » l'emporte sur « course », parce qu'il est plus précis et
    /// qu'un titre porte souvent les deux.
    @Test func lePlusPreciseGagne() {
        #expect(TrainingImport.sport(depuis: "Course en trail") == .trailRun)
    }

    @Test("la distance se lit en kilomètres", arguments: [
        ("SL 18 km", 18000.0),
        ("18,5 km faciles", 18500.0),
        ("Natation 2000 m", 2000.0),
    ])
    func laDistanceSeLit(_ texte: String, _ attendu: Double) {
        #expect(TrainingImport.distance(depuis: texte) == attendu)
    }

    /// Un fractionné en côte n'est pas une sortie de quatre cents mètres.
    @Test func lesPetitsMetresNeSontPasUneDistance() {
        #expect(TrainingImport.distance(depuis: "6×400 m en côte") == nil)
    }

    @Test("la durée se lit sous ses trois écritures", arguments: [
        ("Sortie 1h30", 5400.0),
        ("Vélo 2 h", 7200.0),
        ("Footing 45'", 2700.0),
        ("Renfo 30 min", 1800.0),
    ])
    func laDureeSeLit(_ texte: String, _ attendu: Double) {
        #expect(TrainingImport.duree(depuis: texte) == attendu)
    }

    @Test("le dénivelé se lit des deux côtés du D+", arguments: [
        ("Trail 18 km D+600", 600.0),
        ("Trail d+ 1200 m", 1200.0),
        ("Trail 800m D+", 800.0),
    ])
    func leDeniveleSeLit(_ texte: String, _ attendu: Double) {
        #expect(TrainingImport.denivele(depuis: texte) == attendu)
    }

    @Test func uneLigneCompleteSeLitDUnCoup() {
        let lu = TrainingImport.lire("  SL 18 km D+600 en 1h45  ")
        #expect(lu.sport == .run)
        #expect(lu.titre == "SL 18 km D+600 en 1h45")
        #expect(lu.distance == 18000)
        #expect(lu.denivele == 600)
        #expect(lu.duree == 6300)
    }

    /// Ce qu'on ne sait pas lire ne s'invente pas — et le titre reste entier,
    /// parce que c'est lui qui porte l'information qu'on a ratée.
    @Test func ceQuOnNeLitPasResteDansLeTitre() {
        let lu = TrainingImport.lire("Repos complet")
        #expect(lu.sport == .other)
        #expect(lu.titre == "Repos complet")
        #expect(lu.distance == nil)
        #expect(lu.duree == nil)
        #expect(lu.denivele == nil)
    }
}
