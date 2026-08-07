import Testing
import Foundation
@testable import Cairn

@Suite("Largeur du volet de détail")
struct DetailPaneWidthTests {
    /// Its own defaults domain, so the suite never reads or writes the width the
    /// app is actually using.
    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "cairn.tests.\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.description)
        return defaults
    }

    @Test("une largeur choisie fait l'aller-retour")
    func savesAndReads() {
        let defaults = makeDefaults()
        DetailPaneWidth.save(487, to: defaults)
        #expect(DetailPaneWidth.saved(from: defaults) == 487)
    }

    @Test("rien d'enregistré ne se lit pas comme zéro")
    func absentIsNil() {
        // `UserDefaults.double(forKey:)` answers 0 for a missing key, and a pane
        // restored to zero is a pane that never reopens.
        #expect(DetailPaneWidth.saved(from: makeDefaults()) == nil)
    }

    @Test("le repli du volet n'écrase pas la largeur choisie")
    func ignoresTheCollapse() {
        // `RootView` shuts the pane by giving it a width of zero whenever there
        // is no selection, and that arrives as an ordinary resize. Recording it
        // would mean reopening at zero for good.
        let defaults = makeDefaults()
        DetailPaneWidth.save(487, to: defaults)
        DetailPaneWidth.save(0, to: defaults)
        #expect(DetailPaneWidth.saved(from: defaults) == 487)
    }

    @Test("le séparateur se place pour rendre au volet sa largeur")
    func placesTheDivider() {
        let position = DetailPaneWidth.dividerPosition(
            detailWidth: 487, totalWidth: 1_537,
            dividerThickness: 1, sidebarWidth: 268, minimumMiddle: 480
        )
        #expect(position == 1_049)
        // The point of the exercise: 1537 − 1049 − 1 leaves the pane at 487.
        #expect(1_537 - (position ?? 0) - 1 == 487)
    }

    @Test("une fenêtre trop étroite laisse AppKit décider")
    func givesUpWhenItDoesNotFit() {
        // Restoring a width the window can no longer hold would squeeze the list
        // to nothing. AppKit's own layout is the better answer here.
        #expect(
            DetailPaneWidth.dividerPosition(
                detailWidth: 900, totalWidth: 1_200,
                dividerThickness: 1, sidebarWidth: 268, minimumMiddle: 480
            ) == nil
        )
    }
}
