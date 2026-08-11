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

    @Test("chaque volet garde sa propre largeur")
    func kindsDoNotShare() {
        let defaults = makeDefaults()
        DetailPaneWidth.save(487, for: .activity, to: defaults)
        DetailPaneWidth.save(240, for: .nutrition, to: defaults)
        #expect(DetailPaneWidth.saved(for: .activity, from: defaults) == 487)
        #expect(DetailPaneWidth.saved(for: .nutrition, from: defaults) == 240)
        // Régler l'un ne dit rien de l'autre : c'est tout l'objet du partage.
        DetailPaneWidth.save(600, for: .activity, to: defaults)
        #expect(DetailPaneWidth.saved(for: .nutrition, from: defaults) == 240)
    }

    @Test("le plancher du volet alimentation est plus bas que celui des activités")
    func nutritionKeepsNarrowerWidths() {
        let defaults = makeDefaults()
        // 100 pt : un repli pour le volet d'activité, une largeur honnête
        // pour le panneau du journal, qui n'a qu'un calendrier à loger.
        DetailPaneWidth.save(100, for: .activity, to: defaults)
        DetailPaneWidth.save(100, for: .nutrition, to: defaults)
        #expect(DetailPaneWidth.saved(for: .activity, from: defaults) == nil)
        #expect(DetailPaneWidth.saved(for: .nutrition, from: defaults) == 100)
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

    @Test("la colonne qui se rouvre redemande sa largeur")
    func asksAgainOnReopening() {
        // Le volet du journal se ferme et se rouvre sans changer de section :
        // c'est cette transition, et elle seule, qui doit redemander la largeur.
        #expect(DetailPaneWidth.shouldRestore(previousWidth: 0, newWidth: 320))
    }

    @Test("une réouverture au plancher redemande quand même")
    func asksAgainEvenWhenAppKitReopensNarrow() {
        // C'est tout le symptôme : AppKit rouvre la colonne à sa largeur
        // minimale. Une réouverture étroite est justement celle qu'il faut
        // corriger, pas celle qu'il faut laisser passer.
        #expect(DetailPaneWidth.shouldRestore(previousWidth: 0, newWidth: 40))
    }

    @Test("le repli n'est pas une réouverture")
    func theCollapseIsNotAReopening() {
        // `RootView` ferme la colonne en lui donnant zéro, et cela arrive comme
        // un redimensionnement ordinaire. Le prendre pour une réouverture
        // rouvrirait le volet que l'app vient de fermer.
        #expect(!DetailPaneWidth.shouldRestore(previousWidth: 487, newWidth: 0))
    }

    @Test("un glissement ordinaire ne redemande rien")
    func anOrdinaryDragAsksNothing() {
        // Sinon la largeur enregistrée reviendrait sous les doigts de
        // l'utilisateur à chaque tiraillement du séparateur.
        #expect(!DetailPaneWidth.shouldRestore(previousWidth: 487, newWidth: 520))
        // Y compris quand le glissement approche de zéro sans l'atteindre :
        // la colonne était ouverte, elle le reste.
        #expect(!DetailPaneWidth.shouldRestore(previousWidth: 5, newWidth: 40))
    }

    @Test("une colonne restée fermée ne redemande rien")
    func aShutColumnAsksNothing() {
        // Deux redimensionnements de suite pendant que le volet est fermé :
        // rien à rouvrir, et surtout aucune largeur de zéro à ressusciter.
        #expect(!DetailPaneWidth.shouldRestore(previousWidth: 0, newWidth: 0))
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
