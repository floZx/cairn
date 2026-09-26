import Testing
import Foundation
@testable import Cairn

@Suite("Journal : une ligne de la liste")
struct JournalRowLayoutTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    @Test("la première phrase mène, la suite coule derrière")
    func splitsFirstSentence() {
        let preview = JournalRowLayout.split("Ce matin j'ai bien amélioré Cairn. Je le trouve top.")
        #expect(preview.lead == "Ce matin j'ai bien amélioré Cairn.")
        #expect(preview.rest == "Je le trouve top.")
        #expect(JournalRowLayout.split("Une seule phrase").rest.isEmpty)
        #expect(JournalRowLayout.split("3:50/km").lead == "3:50/km")
    }

    @Test("une note devient un paragraphe, sans ses marques ni ses images")
    func proseJoinsBlocks() {
        let prose = JournalRowLayout.prose(of: "# Matin\nBonne séance.\n\n- vent\n![](p.jpg)")
        #expect(prose == "Matin Bonne séance. vent")
    }

    @Test("un jour sans note mène par le nom de ce qui a écrit")
    func elsewhereLeadsWithSource() {
        let day = JournalDay(
            date: key("2026-09-22"), elsewhereNotes: ["3:50/km"], elsewhereSources: ["8x30″/30″"]
        )
        #expect(JournalRowLayout.preview(of: day) == .init(lead: "8x30″/30″", rest: "3:50/km"))
    }

    @Test("un en-tête par mois, et la ligne du tableau les compte")
    func monthsAndTableRows() {
        let days = ["2026-09-26", "2026-09-25", "2026-08-31", "2026-08-02", "2026-07-14"]
            .map { JournalDay(date: key($0), note: JournalFileNote(date: key($0), text: "x")) }
        let months = JournalRowLayout.months(of: days)
        #expect(months.map(\.title) == ["SEPTEMBRE 2026", "AOÛT 2026", "JUILLET 2026"])
        #expect(months.map(\.days.count) == [2, 2, 1])
        // En-tête de septembre en ligne 0, puis ses deux jours ; l'en-tête
        // d'août en 3, etc.
        #expect((0..<5).map { JournalRowLayout.tableRow(forDay: $0, in: days) } == [1, 2, 4, 5, 7])
        #expect(JournalRowLayout.tableRows(forDays: [0, 4], in: days) == [1, 7])
    }

    @Test("la tuile dit le jour abrégé et son numéro")
    func tile() {
        let tile = JournalRowLayout.tile(for: key("2026-09-26"))
        #expect(tile.weekday == "SAM")
        #expect(tile.day == "26")
        #expect(JournalRowLayout.tile(for: key("2026-09-08")).day == "8")
    }
}

@Suite("Journal : l'en-tête d'une journée")
struct JournalHeadingTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    @Test("le titre dit le jour et la date, la majuscule en tête")
    func title() {
        #expect(JournalRowLayout.title(for: key("2026-09-26")) == "Samedi 26 septembre")
    }

    @Test("la ligne dessous : l'année, quand, et combien de sorties")
    func subtitle() {
        let today = key("2026-09-26")
        #expect(JournalRowLayout.subtitle(for: today, activities: 2, today: today) == "2026 · aujourd'hui · 2 activités")
        #expect(JournalRowLayout.subtitle(for: key("2026-09-25"), activities: 1, today: today) == "2026 · hier · 1 activité")
        #expect(JournalRowLayout.subtitle(for: key("2026-09-23"), activities: 0, today: today) == "2026 · mercredi")
        #expect(JournalRowLayout.subtitle(for: key("2026-09-08"), activities: 0, today: today) == "2026")
    }
}
