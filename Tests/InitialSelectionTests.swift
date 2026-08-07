import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Sélection à l'ouverture de la liste")
@MainActor
struct InitialSelectionTests {
    private func makeRows() throws -> (context: ModelContext, rows: [Activity]) {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let rows = (0..<3).map { index -> Activity in
            let activity = Activity(
                stravaID: Int64(index), name: "Sortie \(index)", sportType: .run
            )
            // The list's default order is newest first, so the first row is the
            // most recent activity — which is what the opening selection means.
            activity.startDate = Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400)
            context.insert(activity)
            return activity
        }
        try context.save()
        return (context, rows)
    }

    @Test("la première ligne est retenue quand rien n'est sélectionné")
    func picksTheFirstRow() throws {
        let (_, rows) = try makeRows()
        #expect(
            ActivityListView.initialSelection(
                rows: rows, current: [], hasAutoSelected: false
            ) == rows[0].id
        )
    }

    @Test("une sélection existante n'est jamais écrasée")
    func leavesAnExistingSelectionAlone() throws {
        let (_, rows) = try makeRows()
        #expect(
            ActivityListView.initialSelection(
                rows: rows, current: [rows[2].id], hasAutoSelected: false
            ) == nil
        )
    }

    @Test("l'ouverture ne se rejoue pas après le premier passage")
    func onlyHappensOnce() throws {
        let (_, rows) = try makeRows()
        // Changing a filter re-instantiates the list; without this the newest
        // activity would be re-selected under the user at each change, including
        // right after they cleared the selection to close the detail pane.
        #expect(
            ActivityListView.initialSelection(
                rows: rows, current: [], hasAutoSelected: true
            ) == nil
        )
    }

    @Test("une liste vide ne sélectionne rien")
    func selectsNothingWhenEmpty() {
        #expect(
            ActivityListView.initialSelection(
                rows: [], current: [], hasAutoSelected: false
            ) == nil
        )
    }
}
