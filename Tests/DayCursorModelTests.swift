import Testing
@testable import Cairn

@Suite("DayCursorModel")
struct DayCursorModelTests {
    @Test("les positions énumèrent en-têtes puis lignes, dans l'ordre")
    func positionsInOrder() {
        let positions = DayCursorModel.positions(rowCounts: [2, 0, 1])
        #expect(positions == [
            DayCursor(mealIndex: 0, rowIndex: nil),
            DayCursor(mealIndex: 0, rowIndex: 0),
            DayCursor(mealIndex: 0, rowIndex: 1),
            DayCursor(mealIndex: 1, rowIndex: nil),
            DayCursor(mealIndex: 2, rowIndex: nil),
            DayCursor(mealIndex: 2, rowIndex: 0),
        ])
    }

    @Test("j descend, k remonte, le compte s'applique, les bords clampent")
    func movesWithCountAndClamps() {
        let counts = [2, 0, 1]
        let start = DayCursorModel.move(from: nil, by: 1, rowCounts: counts)
        #expect(start == DayCursor(mealIndex: 0, rowIndex: nil))
        let down2 = DayCursorModel.move(from: start, by: 2, rowCounts: counts)
        #expect(down2 == DayCursor(mealIndex: 0, rowIndex: 1))
        // Au-delà du bas : clamp sur la dernière position.
        let far = DayCursorModel.move(from: down2, by: 99, rowCounts: counts)
        #expect(far == DayCursor(mealIndex: 2, rowIndex: 0))
        #expect(DayCursorModel.move(from: far, by: -99, rowCounts: counts)
            == DayCursor(mealIndex: 0, rowIndex: nil))
    }

    @Test("depuis rien, k part du bas")
    func upFromNothingStartsAtBottom() {
        #expect(DayCursorModel.move(from: nil, by: -1, rowCounts: [1])
            == DayCursor(mealIndex: 0, rowIndex: 0))
    }

    @Test("le clamp resitue un curseur périmé")
    func clampReseatsStaleCursor() {
        // La ligne 1 du repas 0 a disparu : on retombe sur la plus proche.
        let stale = DayCursor(mealIndex: 0, rowIndex: 1)
        #expect(DayCursorModel.clamp(stale, rowCounts: [1, 0])
            == DayCursor(mealIndex: 0, rowIndex: 0))
        // Le repas 2 n'existe plus.
        #expect(DayCursorModel.clamp(
            DayCursor(mealIndex: 2, rowIndex: nil), rowCounts: [1]
        ) == DayCursor(mealIndex: 0, rowIndex: 0))
        // Rien à montrer : nil.
        #expect(DayCursorModel.clamp(stale, rowCounts: []) == nil)
        #expect(DayCursorModel.clamp(nil, rowCounts: [1]) == nil)
    }
}
