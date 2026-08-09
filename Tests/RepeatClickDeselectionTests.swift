import Testing
import Foundation
@testable import Cairn

@Suite("Déselection au reclic")
struct RepeatClickDeselectionTests {
    @Test("recliquer la seule ligne sélectionnée la désélectionne")
    func clickingTheLoneSelectedRowDeselects() {
        #expect(RepeatClickDeselection.shouldDeselect(
            clickedRow: 3, selected: IndexSet(integer: 3)
        ))
    }

    @Test("cliquer une autre ligne ne fait que déplacer la sélection")
    func clickingAnotherRowKeepsSelecting() {
        #expect(!RepeatClickDeselection.shouldDeselect(
            clickedRow: 4, selected: IndexSet(integer: 3)
        ))
    }

    @Test("avec plusieurs lignes, le clic simple resserre la sélection")
    func multiSelectionCollapsesInsteadOfDeselecting() {
        #expect(!RepeatClickDeselection.shouldDeselect(
            clickedRow: 3, selected: IndexSet([1, 3, 5])
        ))
    }

    @Test("un clic hors des lignes ne désélectionne pas ici")
    func clickOutsideAnyRowIsNotOurs() {
        // -1 est ce que renvoie AppKit sous la dernière ligne ; le vide se
        // gère ailleurs, pas en avalant l'évènement.
        #expect(!RepeatClickDeselection.shouldDeselect(
            clickedRow: -1, selected: IndexSet(integer: 3)
        ))
    }

    @Test("sans sélection, rien à défaire")
    func emptySelectionDeselectsNothing() {
        #expect(!RepeatClickDeselection.shouldDeselect(
            clickedRow: 3, selected: IndexSet()
        ))
    }
}
