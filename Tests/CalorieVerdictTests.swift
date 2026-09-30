import Testing
@testable import Cairn

@Suite("Bilan calorique du calendrier")
struct CalorieVerdictTests {
    @Test("les couleurs de la jauge, jour par jour, et rien sans objectif ni sous l'objectif")
    func verdicts() {
        let verdicts = CalorieVerdict.verdicts(
            kcalByDay: [
                "2026-09-01": 1750, "2026-09-02": 3000, "2026-09-03": 1000,
                "2026-09-04": 1750,
            ],
            targets: ["2026-09-01": 1750, "2026-09-02": 1750, "2026-09-03": 1750]
        )
        #expect(verdicts["2026-09-01"] == .onTarget)
        #expect(verdicts["2026-09-02"] == .heavy)
        #expect(verdicts["2026-09-03"] == nil)
        #expect(verdicts["2026-09-04"] == nil)
    }
}
