import Testing
@testable import Cairn

@Suite("Bilan calorique du calendrier")
struct CalorieVerdictTests {
    @Test("les couleurs de la jauge jour par jour, gris dessous, rien sans objectif")
    func verdicts() {
        let verdicts = CalorieVerdict.verdicts(
            kcalByDay: [
                "2026-09-01": 1750, "2026-09-02": 3000, "2026-09-03": 1000,
                "2026-09-04": 1750, "2026-09-05": 500,
            ],
            targets: [
                "2026-09-01": 1750, "2026-09-02": 1750, "2026-09-03": 1750,
                "2026-09-05": 1750,
            ],
            today: DateKey(raw: "2026-09-05")!
        )
        #expect(verdicts["2026-09-01"] == .onTarget)
        #expect(verdicts["2026-09-02"] == .heavy)
        #expect(verdicts["2026-09-03"] == .under)
        #expect(verdicts["2026-09-04"] == nil)
        // Aujourd'hui n'est pas encore « sous » : la journée n'est pas finie.
        #expect(verdicts["2026-09-05"] == nil)
    }
}
