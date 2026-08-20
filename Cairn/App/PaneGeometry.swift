import AppKit

/// La largeur des volets, écran par écran, sous des clés qui survivent aux
/// reconstructions.
///
/// AppKit sauvegarde déjà la géométrie d'un `NSSplitView`, mais sous un nom
/// qu'il dérive du **type Swift mangé de la vue racine**, chaîne de
/// modificateurs comprise :
///
///     NSSplitView Subview Frames SwiftUI.ModifiedContent<SwiftUI.Modified…
///     Content<Cairn.RootView, …_EnvironmentKeyWritingModifier<…>>,
///     SwiftUI._TaskModifier2>-1-AppWindow-1, SidebarNavigationSplitView
///
/// Tout ce qui compose ce nom change pour des raisons qui n'ont rien à voir
/// avec la géométrie : ajouter un seul `.task` à la vue racine forge une clé
/// neuve, et renommer le module de StravaLocal en Cairn l'avait fait avant.
/// Trois générations de clés orphelines dormaient dans les préférences, chacune
/// tenant des largeurs que plus rien ne relirait — et l'utilisateur redonnait
/// aux volets, build après build, la taille qu'il leur avait déjà donnée.
///
/// Renommer la sauvegarde d'AppKit ne suffit pas : la restauration a lieu quand
/// le split view rejoint la fenêtre, avant qu'aucune sonde à nous ne puisse
/// tourner, si bien qu'une clé renommée s'écrit mais ne se relit jamais. D'où
/// ces largeurs-ci, tenues et reposées par nous.
///
/// **Deux largeurs par écran et non trois**, et ce n'est pas une économie : un
/// split view de trois colonnes dans une fenêtre de largeur fixe n'a que deux
/// degrés de liberté. La latérale et le détail sont ceux qu'on déplace ; le
/// milieu est ce qui reste, et le ranger en plus reviendrait à garder une
/// valeur qui contredirait les deux autres un jour sur deux.
enum PaneGeometry {
    /// L'écran affiché, et donc à qui ces largeurs appartiennent.
    ///
    /// Un par section, parce qu'elles ne montrent pas la même chose dans la
    /// même colonne : la barre latérale porte un calendrier dans le journal et
    /// dans l'alimentation, des étiquettes dans le journal seul, des filtres de
    /// sport sur les écrans d'activités ; le volet de droite porte une carte et
    /// quatre rangées de chiffres sur une sortie, un éditeur dans le journal,
    /// du texte sur la fiche d'une personne. Une largeur pour tout le monde
    /// voulait dire qu'élargir l'une rétrécissait l'autre.
    enum Ecran: String, CaseIterable, Sendable {
        case activites
        case carte
        case statistiques
        case plan
        case journal
        case people
        case alimentation
        case poids
    }

    enum Colonne: String, Sendable {
        case laterale
        case detail
    }

    /// La clé sous laquelle une largeur est rangée.
    ///
    /// Les trois écrans qui avaient déjà la leur gardent leur ancien nom : une
    /// largeur déjà réglée à la main n'a pas à être perdue par le correctif
    /// qui vient précisément empêcher qu'on les perde.
    static func key(_ ecran: Ecran, _ colonne: Colonne) -> String {
        if colonne == .detail {
            switch ecran {
            case .activites: return "detailPaneWidth.v1"
            case .alimentation: return "nutritionPaneWidth.v1"
            case .journal: return "journalPaneWidth.v1"
            default: break
            }
        }
        return "volet.\(ecran.rawValue).\(colonne.rawValue)"
    }

    /// En dessous, le volet n'est pas étroit : il est fermé.
    ///
    /// `RootView` ferme la colonne de droite à zéro dès qu'elle n'a rien à
    /// montrer, et cette fermeture arrive comme un redimensionnement ordinaire.
    /// L'enregistrer voudrait dire rouvrir à zéro pour toujours. La barre
    /// latérale se replie de la même façon, à la demande.
    static func floor(_ ecran: Ecran, _ colonne: Colonne) -> Double {
        switch colonne {
        case .laterale: 120
        case .detail:
            switch ecran {
            // Le petit calendrier et les totaux d'une journée tiennent dans
            // bien moins qu'une carte : son plancher doit descendre plus bas,
            // sans quoi ses largeurs honnêtes passeraient pour des fermetures.
            case .alimentation: 80
            default: 120
            }
        }
    }

    static func save(
        _ width: Double, _ ecran: Ecran, _ colonne: Colonne,
        to defaults: UserDefaults = .standard
    ) {
        guard width >= floor(ecran, colonne) else { return }
        defaults.set(width, forKey: key(ecran, colonne))
    }

    static func saved(
        _ ecran: Ecran, _ colonne: Colonne, from defaults: UserDefaults = .standard
    ) -> Double? {
        let width = defaults.double(forKey: key(ecran, colonne))
        return width >= floor(ecran, colonne) ? width : nil
    }

    /// Si un redimensionnement qui a mené la colonne de `previousWidth` à
    /// `newWidth` est le moment de redemander sa largeur.
    ///
    /// La colonne se ferme et se rouvre sans jamais changer d'écran : la liste
    /// du journal ne sélectionne rien en arrivant, donc sa colonne est fermée à
    /// l'ouverture de la section et à chaque désélection. Un passage de main
    /// n'est donc pas le seul moment où une largeur doit être redemandée — une
    /// réouverture en est un aussi.
    ///
    /// Fermée veut dire exactement zéro, ce que `RootView` donne à la colonne
    /// quand elle n'a rien à montrer. Un diviseur tiré jusqu'à quelques points
    /// reste ouvert, et doit rester où on l'a mis.
    static func shouldRestore(previousWidth: Double, newWidth: Double) -> Bool {
        previousWidth <= 0 && newWidth > 0
    }

    /// Où poser le dernier diviseur pour que le volet de droite fasse `width`,
    /// ou nil quand c'est impossible sans écraser le milieu sous
    /// `minimumMiddle`.
    ///
    /// Rendre nil plutôt que de rogner : une fenêtre plus étroite que les
    /// largeurs qu'on lui a laissées est un cas où la mise en page d'AppKit est
    /// la meilleure réponse, et forcer une position réduirait la liste à rien.
    static func dividerPosition(
        detailWidth: Double, totalWidth: Double,
        dividerThickness: Double, sidebarWidth: Double, minimumMiddle: Double
    ) -> Double? {
        let position = totalWidth - detailWidth - dividerThickness
        guard position - sidebarWidth - dividerThickness >= minimumMiddle else {
            return nil
        }
        return position
    }

    /// Où poser le premier diviseur pour que la barre latérale fasse `width`,
    /// ou nil quand il ne resterait pas `minimumMiddle` au milieu.
    ///
    /// Le détail est passé en paramètre plutôt que lu : au moment où l'on pose
    /// la latérale, la colonne de droite peut être fermée, et la place qu'elle
    /// occupera est celle qu'on s'apprête à lui rendre.
    static func sidebarPosition(
        sidebarWidth: Double, totalWidth: Double,
        dividerThickness: Double, detailWidth: Double, minimumMiddle: Double
    ) -> Double? {
        let reste = totalWidth - sidebarWidth - detailWidth - 2 * dividerThickness
        guard reste >= minimumMiddle else { return nil }
        return sidebarWidth
    }
}
