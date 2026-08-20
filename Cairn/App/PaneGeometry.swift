import AppKit
import os

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
    /// Le journal des largeurs, le temps de comprendre.
    ///
    /// Posé parce que « c'est complètement aléatoire » ne se corrige pas en
    /// raisonnant : il faut voir ce qui est écrit, quand, et par quel chemin.
    ///
    /// Dans un fichier et non dans le journal unifié : les messages de niveau
    /// `debug` n'y sont pas persistés, et `log show` n'a donc rien rendu du
    /// premier essai. Un fichier ne se discute pas.
    ///
    ///     ~/Library/Logs/Cairn-volets.log
    ///
    /// À retirer une fois la cause trouvée.
    nonisolated(unsafe) private static let fichier: URL? = {
        guard let dossier = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Logs") else { return nil }
        try? FileManager.default.createDirectory(
            at: dossier, withIntermediateDirectories: true
        )
        return dossier.appendingPathComponent("Cairn-volets.log")
    }()

    private static let horloge: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func tracer(_ ligne: String) {
        guard let fichier else { return }
        let texte = "\(horloge.string(from: Date()))  \(ligne)\n"
        guard let octets = texte.data(using: .utf8) else { return }
        if let poignee = try? FileHandle(forWritingTo: fichier) {
            defer { try? poignee.close() }
            _ = try? poignee.seekToEnd()
            try? poignee.write(contentsOf: octets)
        } else {
            try? octets.write(to: fichier)
        }
    }
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
        guard width >= floor(ecran, colonne) else {
            tracer("refus  \(ecran.rawValue) \(colonne.rawValue) \(Int(width))")
            return
        }
        tracer("ÉCRIT  \(ecran.rawValue) \(colonne.rawValue) \(Int(width))")
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
    /// Rogné plutôt que refusé, et c'est le correctif du défaut le plus grave
    /// de cette mécanique.
    ///
    /// Le refus pur était mesuré dans le journal des largeurs : une fenêtre de
    /// 1426 points ne peut pas rendre 869 au volet de droite sans écraser le
    /// milieu, donc rien n'était posé — et la colonne restait à la largeur par
    /// défaut de macOS. Comme quitter l'écran enregistrait ce qui était à
    /// l'écran, la largeur qu'on avait réglée était remplacée par ce défaut, et
    /// perdue pour de bon. Chaque aller-retour en détruisait une de plus :
    /// c'est tout le « complètement aléatoire ».
    ///
    /// La largeur rangée, elle, n'est **jamais** modifiée par ce rognage : la
    /// fenêtre s'élargira, et le volet retrouvera sa taille.
    static func dividerPosition(
        detailWidth: Double, totalWidth: Double,
        dividerThickness: Double, sidebarWidth: Double, minimumMiddle: Double
    ) -> Double? {
        let ideale = totalWidth - detailWidth - dividerThickness
        let plusAGauche = sidebarWidth + dividerThickness + minimumMiddle
        let position = max(ideale, plusAGauche)
        // Sous le plancher du volet, il n'y a plus de volet à rendre : mieux
        // vaut laisser AppKit faire que d'ouvrir une bande de trente points.
        guard totalWidth - position - dividerThickness >= 80 else { return nil }
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
