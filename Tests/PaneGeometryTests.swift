import Testing
import Foundation
@testable import Cairn

@Suite("Largeur des volets")
struct PaneGeometryTests {
    /// Its own defaults domain, so the suite never reads or writes the width the
    /// app is actually using.
    ///
    /// Le balai est ici et non dans un `defer` parce qu'il n'y en a aucun :
    /// ces tests prennent un domaine et le laissent. Chaque appel ramasse donc
    /// les fichiers laissés par les précédents, de cette exécution comme des
    /// précédentes — voir `ThrowawayDefaults.sweep(prefix:)`, qui dit pourquoi
    /// retirer le fichier de sa propre suite ne suffirait pas.
    ///
    /// Le préfixe est celui de cette suite seule. Il valait `cairn.tests.`,
    /// qui est aussi le début de `cairn.tests.mirror.` : balayer sous ce
    /// nom-là aurait emporté les fichiers d'une suite du miroir en train de
    /// tourner à côté.
    private static let suitePrefix = "detail-pane-width-tests-"

    private func makeDefaults() -> UserDefaults {
        ThrowawayDefaults.sweep(prefix: Self.suitePrefix)
        let defaults = UserDefaults(
            suiteName: "\(Self.suitePrefix)\(UUID().uuidString)"
        )!
        defaults.removePersistentDomain(forName: defaults.description)
        return defaults
    }

    @Test("une largeur choisie fait l'aller-retour")
    func savesAndReads() {
        let defaults = makeDefaults()
        PaneGeometry.save(487, .activites, .detail, to: defaults)
        #expect(PaneGeometry.saved(.activites, .detail, from: defaults) == 487)
    }

    @Test("rien d'enregistré ne se lit pas comme zéro")
    func absentIsNil() {
        // `UserDefaults.double(forKey:)` answers 0 for a missing key, and a pane
        // restored to zero is a pane that never reopens.
        #expect(PaneGeometry.saved(.activites, .detail, from: makeDefaults()) == nil)
    }

    @Test("le repli du volet n'écrase pas la largeur choisie")
    func ignoresTheCollapse() {
        // `RootView` shuts the pane by giving it a width of zero whenever there
        // is no selection, and that arrives as an ordinary resize. Recording it
        // would mean reopening at zero for good.
        let defaults = makeDefaults()
        PaneGeometry.save(487, .activites, .detail, to: defaults)
        PaneGeometry.save(0, .activites, .detail, to: defaults)
        #expect(PaneGeometry.saved(.activites, .detail, from: defaults) == 487)
    }

    @Test("chaque écran garde sa propre largeur")
    func lesEcransNePartagentPas() {
        let defaults = makeDefaults()
        PaneGeometry.save(487, .activites, .detail, to: defaults)
        PaneGeometry.save(240, .alimentation, .detail, to: defaults)
        #expect(PaneGeometry.saved(.activites, .detail, from: defaults) == 487)
        #expect(PaneGeometry.saved(.alimentation, .detail, from: defaults) == 240)
        // Régler l'un ne dit rien de l'autre : c'est tout l'objet du partage.
        PaneGeometry.save(600, .activites, .detail, to: defaults)
        #expect(PaneGeometry.saved(.alimentation, .detail, from: defaults) == 240)
    }

    /// Le défaut signalé : la page d'une personne partageait sa largeur avec
    /// la fiche d'une sortie, alors que l'une porte du texte et l'autre une
    /// carte et quatre rangées de chiffres.
    @Test("People ne partage plus avec les activités")
    func peopleNePartagePlus() {
        let defaults = makeDefaults()
        PaneGeometry.save(487, .activites, .detail, to: defaults)
        PaneGeometry.save(340, .people, .detail, to: defaults)
        #expect(PaneGeometry.saved(.activites, .detail, from: defaults) == 487)
        #expect(PaneGeometry.saved(.people, .detail, from: defaults) == 340)
    }

    /// Les deux colonnes libres ne se marchent pas dessus.
    @Test("la latérale et le détail sont rangés à part")
    func lesDeuxColonnesSontDistinctes() {
        let defaults = makeDefaults()
        PaneGeometry.save(268, .journal, .laterale, to: defaults)
        PaneGeometry.save(580, .journal, .detail, to: defaults)
        #expect(PaneGeometry.saved(.journal, .laterale, from: defaults) == 268)
        #expect(PaneGeometry.saved(.journal, .detail, from: defaults) == 580)
    }

    /// Les trois écrans qui avaient déjà leur largeur gardent leur ancienne
    /// clé : le correctif qui vient empêcher qu'on perde les largeurs ne doit
    /// pas commencer par les perdre.
    @Test("les anciennes clés sont conservées", arguments: [
        (PaneGeometry.Ecran.activites, "detailPaneWidth.v1"),
        (.alimentation, "nutritionPaneWidth.v1"),
        (.journal, "journalPaneWidth.v1"),
    ])
    func lesAnciennesClesTiennent(_ ecran: PaneGeometry.Ecran, _ cle: String) {
        #expect(PaneGeometry.key(ecran, .detail) == cle)
        // La latérale, elle, est neuve partout.
        #expect(PaneGeometry.key(ecran, .laterale).hasPrefix("volet."))
    }

    @Test("le plancher du volet alimentation est plus bas que celui des activités")
    func nutritionKeepsNarrowerWidths() {
        let defaults = makeDefaults()
        // 100 pt : un repli pour le volet d'activité, une largeur honnête
        // pour le panneau du journal, qui n'a qu'un calendrier à loger.
        PaneGeometry.save(100, .activites, .detail, to: defaults)
        PaneGeometry.save(100, .alimentation, .detail, to: defaults)
        #expect(PaneGeometry.saved(.activites, .detail, from: defaults) == nil)
        #expect(PaneGeometry.saved(.alimentation, .detail, from: defaults) == 100)
    }

    @Test("le premier séparateur rend à la latérale sa largeur")
    func placeLePremierSeparateur() {
        let position = PaneGeometry.sidebarPosition(
            sidebarWidth: 268, totalWidth: 1_537,
            dividerThickness: 1, detailWidth: 487, minimumMiddle: 480
        )
        #expect(position == 268)
        // 1537 − 268 − 487 − 2 laisse 780 au milieu, largement au-dessus du
        // plancher.
        #expect(1_537 - 268 - 487 - 2 >= 480)
    }

    /// Une fenêtre trop étroite pour les trois : la mise en page d'AppKit vaut
    /// mieux qu'une position forcée qui réduirait la liste à rien.
    @Test("une fenêtre trop étroite ne se laisse pas forcer")
    func uneFenetreTropEtroiteRendNil() {
        #expect(PaneGeometry.sidebarPosition(
            sidebarWidth: 400, totalWidth: 1_000,
            dividerThickness: 1, detailWidth: 500, minimumMiddle: 480
        ) == nil)
    }

    /// Le défaut le plus grave, et celui que le journal des largeurs a
    /// montré : une fenêtre trop étroite faisait **refuser** la restauration,
    /// la colonne restait au défaut de macOS, et quitter l'écran enregistrait
    /// ce défaut à la place de la largeur réglée. Chaque aller-retour en
    /// détruisait une.
    @Test("une fenêtre trop étroite rogne au lieu de renoncer")
    func rogneAuLieuDeRenoncer() {
        // 1426 de large, 268 de latérale : rendre 869 au détail ne laisserait
        // que 287 au milieu, sous son plancher de 480.
        let position = PaneGeometry.dividerPosition(
            detailWidth: 869, totalWidth: 1_426,
            dividerThickness: 1, sidebarWidth: 268, minimumMiddle: 480
        )
        let position2 = try! #require(position)
        // Le milieu garde exactement son plancher, et le volet prend le reste.
        #expect(1_426 - position2 - 1 == 676)
        #expect(position2 - 268 - 1 == 480)
    }

    /// Il reste un cas où renoncer est juste : quand il ne resterait qu'une
    /// bande au volet, la mise en page d'AppKit vaut mieux.
    @Test("sous une bande, on laisse faire")
    func sousUneBandeOnLaisseFaire() {
        #expect(PaneGeometry.dividerPosition(
            detailWidth: 400, totalWidth: 800,
            dividerThickness: 1, sidebarWidth: 268, minimumMiddle: 480
        ) == nil)
    }

    @Test("le séparateur se place pour rendre au volet sa largeur")
    func placesTheDivider() {
        let position = PaneGeometry.dividerPosition(
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
        #expect(PaneGeometry.shouldRestore(previousWidth: 0, newWidth: 320))
    }

    @Test("une réouverture au plancher redemande quand même")
    func asksAgainEvenWhenAppKitReopensNarrow() {
        // C'est tout le symptôme : AppKit rouvre la colonne à sa largeur
        // minimale. Une réouverture étroite est justement celle qu'il faut
        // corriger, pas celle qu'il faut laisser passer.
        #expect(PaneGeometry.shouldRestore(previousWidth: 0, newWidth: 40))
    }

    @Test("le repli n'est pas une réouverture")
    func theCollapseIsNotAReopening() {
        // `RootView` ferme la colonne en lui donnant zéro, et cela arrive comme
        // un redimensionnement ordinaire. Le prendre pour une réouverture
        // rouvrirait le volet que l'app vient de fermer.
        #expect(!PaneGeometry.shouldRestore(previousWidth: 487, newWidth: 0))
    }

    @Test("un glissement ordinaire ne redemande rien")
    func anOrdinaryDragAsksNothing() {
        // Sinon la largeur enregistrée reviendrait sous les doigts de
        // l'utilisateur à chaque tiraillement du séparateur.
        #expect(!PaneGeometry.shouldRestore(previousWidth: 487, newWidth: 520))
        // Y compris quand le glissement approche de zéro sans l'atteindre :
        // la colonne était ouverte, elle le reste.
        #expect(!PaneGeometry.shouldRestore(previousWidth: 5, newWidth: 40))
    }

    @Test("une colonne restée fermée ne redemande rien")
    func aShutColumnAsksNothing() {
        // Deux redimensionnements de suite pendant que le volet est fermé :
        // rien à rouvrir, et surtout aucune largeur de zéro à ressusciter.
        #expect(!PaneGeometry.shouldRestore(previousWidth: 0, newWidth: 0))
    }

    /// Le comportement a changé, et c'est délibéré : renoncer laissait la
    /// colonne au défaut de macOS, que le passage à l'écran suivant
    /// enregistrait ensuite à la place de la largeur réglée. Rogner rend ce
    /// qu'on peut et ne touche pas à ce qui est rangé.
    @Test("une fenêtre trop étroite rend ce qu'elle peut")
    func rendCeQuEllePeut() {
        let position = try! #require(
            PaneGeometry.dividerPosition(
                detailWidth: 900, totalWidth: 1_200,
                dividerThickness: 1, sidebarWidth: 268, minimumMiddle: 480
            )
        )
        // Le milieu à son plancher, le volet prend les 451 qui restent.
        #expect(position == 749)
        #expect(1_200 - position - 1 == 450)
    }
}
