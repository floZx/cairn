import Testing
@testable import Cairn

@Suite("WeightPeriod")
struct WeightPeriodTests {
    @Test("chaque période porte sa fenêtre en jours")
    func daysPerPeriod() {
        #expect(WeightPeriod.thirtyDays.days == 30)
        #expect(WeightPeriod.ninetyDays.days == 90)
        #expect(WeightPeriod.year.days == 365)
        #expect(WeightPeriod.all.days == nil)
    }

    @Test("le rawValue est stable pour l'AppStorage")
    func rawValuesAreStable() {
        // Persisted in user defaults: renaming a case would silently reset
        // the user's chosen window.
        #expect(WeightPeriod(rawValue: "thirtyDays") == .thirtyDays)
        #expect(WeightPeriod(rawValue: "all") == .all)
    }
}
