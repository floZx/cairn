import Testing
import AppKit
@testable import Cairn

@Suite("Hauteur de ligne fixée sur le tableau")
@MainActor
struct FixedTableRowHeightTests {
    /// A container view holding the given subviews, in order.
    private func container(_ subviews: [NSView]) -> NSView {
        let view = NSView()
        subviews.forEach(view.addSubview)
        return view
    }

    @Test("la sonde trouve le tableau voisin, pas ses propres descendants")
    func findsTheSiblingTable() {
        let probe = NSView()
        let table = NSTableView()
        _ = container([container([table]), probe])

        #expect(FixedTableRowHeight.tableView(near: probe) === table)
    }

    @Test("c'est le tableau le plus proche qui est retenu")
    func prefersTheNearestTable() {
        // The shape that matters: the sidebar is a `List`, so it is an
        // `NSTableView` too. Searching from the window down would be a coin toss
        // between the two — this must find the one next to the probe.
        let sidebarTable = NSTableView()
        let listTable = NSTableView()
        let probe = NSView()
        _ = container([
            container([sidebarTable]),
            container([container([listTable]), probe]),
        ])

        #expect(FixedTableRowHeight.tableView(near: probe) === listTable)
    }

    @Test("sans tableau nulle part, la sonde ne trouve rien")
    func findsNothingWithoutATable() {
        let probe = NSView()
        _ = container([container([NSView()]), probe])

        #expect(FixedTableRowHeight.tableView(near: probe) == nil)
    }

    @Test("le défilement ne sort jamais des lignes existantes")
    func scrollingStaysInRange() {
        // The keyboard asks for a row index computed from the model, and the
        // table it lands on may not have caught up yet — during a filter change,
        // or before the first rows exist at all. `scrollRowToVisible` traps on an
        // index it does not have, so the check belongs here rather than nowhere.
        let scroller = TableScroller()

        // No table found yet: the probe may still be retrying.
        scroller.scroll(toRow: 3)

        let table = NSTableView()
        let probe = NSView()
        _ = container([container([table]), probe])
        scroller.attachForTesting(probe)
        // An empty table has no row 0 to reach.
        scroller.scroll(toRow: 0)
        scroller.scroll(toRow: -1)
        scroller.scroll(toRow: 9_999)
        // Reaching here at all is the assertion: none of those may trap.
        #expect(table.numberOfRows == 0)
    }

    @Test("une demande de focus attend qu'un tableau existe")
    func focusWaitsForATable() {
        // Switching presentation destroys the table the keyboard was in and
        // builds another, so the request is made before there is anything to
        // give focus to. Fired into the void, it would simply be lost and the
        // keyboard would stay dead until the user clicked.
        let scroller = TableScroller()
        scroller.focusWhenAttached()
        #expect(scroller.hasPendingFocus)

        // A probe with no table under it cannot give focus either, so the
        // request survives that too.
        scroller.attachForTesting(NSView())
        #expect(scroller.hasPendingFocus)
    }

    @Test("un tableau encore vide fait patienter au lieu de figer une hauteur")
    func waitsForRows() {
        let table = NSTableView()
        table.usesAutomaticRowHeights = true

        // False means "retry": pinning the height now would freeze whatever
        // AppKit answers for a table with nothing in it.
        #expect(FixedTableRowHeight.apply(to: table) == false)
        #expect(table.usesAutomaticRowHeights)
    }

    @Test("un tableau déjà en hauteur fixe n'est pas retouché")
    func leavesAFixedTableAlone() {
        let table = NSTableView()
        table.usesAutomaticRowHeights = false
        table.rowHeight = 42

        // True means "done, stop retrying" — and the height AppKit or SwiftUI
        // chose must survive untouched.
        #expect(FixedTableRowHeight.apply(to: table) == true)
        #expect(table.rowHeight == 42)
    }
}
