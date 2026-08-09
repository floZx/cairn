import Testing
import Foundation
@testable import Cairn

@Suite("MiniCalendarModel")
struct MiniCalendarModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    @Test("août 2026 : samedi 1er, lundi en tête, 31 jours")
    func august2026() throws {
        let weeks = MiniCalendarModel.weeks(
            containing: DateKey(raw: "2026-08-08")!, calendar: calendar
        )
        // Le 1er août 2026 est un samedi : 5 cases vides devant.
        #expect(weeks[0].prefix(5).allSatisfy { $0 == nil })
        #expect(weeks[0][5]?.raw == "2026-08-01")
        #expect(weeks[0][6]?.raw == "2026-08-02")
        // Toutes les semaines font 7 cases, et on retrouve les 31 jours.
        #expect(weeks.allSatisfy { $0.count == 7 })
        let days = weeks.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
        #expect(days.first?.raw == "2026-08-01")
        #expect(days.last?.raw == "2026-08-31")
    }

    @Test("un mois commençant un lundi n'a pas de cases vides devant")
    func mondayStartHasNoLeadingGap() throws {
        // Juin 2026 commence un lundi.
        let weeks = MiniCalendarModel.weeks(
            containing: DateKey(raw: "2026-06-15")!, calendar: calendar
        )
        #expect(weeks[0][0]?.raw == "2026-06-01")
    }
}
