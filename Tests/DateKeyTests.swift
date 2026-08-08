// Tests/DateKeyTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("DateKey")
struct DateKeyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    @Test("une Date se projette sur le jour calendaire local")
    func fromDate() {
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 8, hour: 23, minute: 30)
        )!
        #expect(DateKey(date, calendar: calendar).raw == "2026-08-08")
    }

    @Test("les chaînes invalides sont refusées", arguments: [
        "abc", "2026-13-01", "2026-08-32", "20260808", "2026-8-8", ""
    ])
    func rejectsInvalidRaw(raw: String) {
        #expect(DateKey(raw: raw) == nil)
    }

    @Test("une chaîne valide fait l'aller-retour")
    func roundTripsRaw() {
        let key = DateKey(raw: "2026-08-08")
        #expect(key?.raw == "2026-08-08")
    }

    @Test("l'ordre lexicographique est l'ordre chronologique")
    func ordersChronologically() {
        #expect(DateKey(raw: "2026-08-08")! < DateKey(raw: "2026-08-09")!)
        #expect(DateKey(raw: "2025-12-31")! < DateKey(raw: "2026-01-01")!)
    }

    @Test("advanced(by:) franchit les frontières de mois")
    func advancesAcrossMonths() {
        let key = DateKey(raw: "2026-08-31")!
        #expect(key.advanced(by: 1, calendar: calendar).raw == "2026-09-01")
        #expect(key.advanced(by: -31, calendar: calendar).raw == "2026-07-31")
    }

    @Test("date() rend minuit local du bon jour")
    func dateIsLocalMidnight() {
        let key = DateKey(raw: "2026-08-08")!
        let date = key.date(calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts.year == 2026 && parts.month == 8 && parts.day == 8)
        #expect(parts.hour == 0)
    }
}
