import Testing
import Foundation
@testable import Cairn

@Suite("FlowRows")
struct FlowRowsTests {
    @Test("les éléments s'accumulent tant qu'ils tiennent, puis passent à la ligne")
    func itemsWrapWhenTheLineIsFull() {
        // 3 × 30 + 2 × 5 d'espacement = 100 : la quatrième déborde.
        let rows = FlowRows.rows(
            widths: [30, 30, 30, 30], spacing: 5, maxWidth: 100
        )
        #expect(rows == [[0, 1, 2], [3]])
    }

    @Test("l'espacement compte dans la largeur disponible")
    func spacingCountsAgainstTheLimit() {
        // Sans espacement les deux tiendraient (50 + 50) ; avec, non.
        #expect(FlowRows.rows(widths: [50, 50], spacing: 0, maxWidth: 100)
                == [[0, 1]])
        #expect(FlowRows.rows(widths: [50, 50], spacing: 6, maxWidth: 100)
                == [[0], [1]])
    }

    @Test("un élément plus large que la ligne occupe sa propre ligne, sans en vider une")
    func oversizedItemGetsItsOwnLine() {
        let rows = FlowRows.rows(
            widths: [40, 300, 40], spacing: 5, maxWidth: 100
        )
        #expect(rows == [[0], [1], [2]])
    }

    @Test("sans élément, aucune ligne")
    func noItemsMeansNoRows() {
        #expect(FlowRows.rows(widths: [], spacing: 5, maxWidth: 100).isEmpty)
    }

    @Test("une largeur infinie garde tout sur une ligne")
    func unboundedWidthKeepsOneRow() {
        let rows = FlowRows.rows(
            widths: [80, 80, 80], spacing: 6, maxWidth: .infinity
        )
        #expect(rows == [[0, 1, 2]])
    }
}
