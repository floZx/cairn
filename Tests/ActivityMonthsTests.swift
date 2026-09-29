import Testing
import Foundation
@testable import Cairn

@Suite("Mois des activités")
struct ActivityMonthsTests {
    private let days = ["2026-09-28", "2026-09-02", "2026-08-30", "2026-07-14"]
        .map { DateKey(raw: $0)! }

    @Test("un en-tête par mois, dans l'ordre des lignes")
    func grouping() {
        let months = ActivityMonths.months(of: days) { $0 }
        #expect(months.map(\.id) == ["2026-09", "2026-08", "2026-07"])
        #expect(months.map(\.rows.count) == [2, 1, 1])
        #expect(months.first?.title == "SEPTEMBRE 2026")
    }

    /// `j` et `k` parlent en sorties, la table en lignes : chaque mois
    /// commencé avant une sortie la pousse d'une ligne.
    @Test("les en-têtes décalent les lignes de la table")
    func tableRows() {
        let rows = (0..<days.count).map {
            ActivityMonths.tableRow(forRow: $0, in: days) { $0 }
        }
        #expect(rows == [1, 2, 4, 6])
    }
}
