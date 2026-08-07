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
