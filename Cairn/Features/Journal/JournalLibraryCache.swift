import Foundation
import SwiftData

/// Ce que la bibliothèque dit des journées : ce qui a été écrit ailleurs que
/// dans le carnet, ce que chaque jour a fait, et les jours que quelque chose
/// nomme.
///
/// Une mémoire de calcul, et il faut dire pourquoi. `RootView` refaisait ces
/// trois choses à chaque évaluation de son corps, donc **à chaque touche
/// frappée** dans une note — le journal enregistre au fil de l'écriture, et
/// chaque frappe rend la vue racine. Or aucune des trois ne dépend de ce qu'on
/// tape : `marks` trie les huit cents sorties et traverse les photos de
/// chacune, `elsewhereNotes` les retrie. Mesuré le 31 août 2026, sur une
/// tranche de deux secondes passée dans le journal : `journalDays` appelée 34
/// fois pour 336 ms, un sixième du fil principal à recalculer l'identique.
///
/// Les trois ensemble et non chacune de son côté : elles traversent la même
/// bibliothèque, et la traverser une fois vaut mieux que trois.
///
/// **Pas `@Observable`.** L'objet est lu *pendant* le rendu, et un observable
/// écrit pendant un rendu en redemande un autre. Ce qu'il tient n'est pas un
/// état de l'application, seulement le souvenir d'un calcul ; ce qui déclenche
/// les rendus reste les `@Query` de la vue, qui bougent quand la bibliothèque
/// bouge — c'est-à-dire aux mêmes moments que l'invalidation ci-dessous.
@MainActor
final class JournalLibraryCache {
    /// Ce qu'une traversée rapporte.
    struct Contenu {
        var elsewhereNotes: [DateKey: [String]] = [:]
        /// Les étiquettes de ces textes, lues une fois pour toutes. Voir
        /// `JournalDay.elsewhereTags` : la barre latérale les relisait à chaque
        /// rendu pour compter ses tags.
        var elsewhereTags: [DateKey: Set<JournalTag>] = [:]
        var marks: [DateKey: JournalDay.Marks] = [:]
        /// Les jours que la **bibliothèque** nomme. Ceux du carnet s'y
        /// ajoutent à la lecture : eux changent à chaque frappe, et ils se
        /// comptent sur les doigts là où les sorties se comptent par
        /// centaines.
        var jours: Set<String> = []
    }

    private var contenu = Contenu()
    private let observers = NotificationObservers()

    /// Le drapeau est posé depuis le fil qui enregistre — le miroir écrit
    /// depuis ses propres contextes, hors du fil principal — d'où le verrou
    /// plutôt qu'un saut vers l'acteur principal. Un saut arriverait un rendu
    /// trop tard, et ce rendu-là montrerait la bibliothèque d'avant : une
    /// photo importée qui n'apparaît qu'au clic suivant est exactement le
    /// genre de bogue qu'une mémoire de calcul doit s'interdire.
    private let verrou = NSLock()
    nonisolated(unsafe) private var perime = true

    /// Ce qu'une écriture doit toucher pour que la traversée soit refaite.
    ///
    /// Le carnet n'en est pas, et c'est tout l'intérêt : il s'enregistre au
    /// fil de l'écriture, soit une fois par temporisation en tapant, et il ne
    /// dit rien de ce qui est calculé ici.
    ///
    /// `nonisolated` parce que la notification arrive sur le fil qui
    /// enregistre : un `Set` de chaînes construit une fois et jamais écrit se
    /// lit de partout.
    nonisolated private static let entitesSuivies: Set<String> = [
        Schema.entityName(for: Activity.self),
        Schema.entityName(for: ActivityPhoto.self),
        Schema.entityName(for: MealNote.self),
        Schema.entityName(for: MealSlot.self),
        Schema.entityName(for: WeightEntry.self),
    ]

    init() {
        observers.observe(ModelContext.didSave) { [weak self] notification in
            guard Self.toucheLaBibliotheque(notification) else { return }
            self?.perimer()
        }
    }

    /// Vrai quand l'écriture concerne ce qui est calculé ici.
    ///
    /// **Dans le doute, vrai.** Une notification dont on ne sait pas lire le
    /// contenu doit périmer : servir une bibliothèque d'avant est un bogue
    /// silencieux — la photo importée qui n'apparaît qu'au clic suivant —
    /// alors qu'une traversée de trop ne coûte que trente millisecondes.
    ///
    /// Mesuré le 31 août 2026 : sans ce tri, taper dans une note refaisait la
    /// traversée toutes les deux secondes, 34 ms à chaque fois, et c'était
    /// devenu le premier poste du fil principal une fois le reste réglé.
    nonisolated static func toucheLaBibliotheque(_ notification: Notification) -> Bool {
        guard let infos = notification.userInfo else { return true }
        let clefs = [
            ModelContext.NotificationKey.insertedIdentifiers,
            ModelContext.NotificationKey.updatedIdentifiers,
            ModelContext.NotificationKey.deletedIdentifiers,
        ]
        var identifiants: [PersistentIdentifier] = []
        for clef in clefs {
            identifiants += infos[clef.rawValue] as? [PersistentIdentifier] ?? []
        }
        // Rien de lisible : on ne sait pas, donc on périme.
        guard !identifiants.isEmpty else { return true }
        return identifiants.contains { entitesSuivies.contains($0.entityName) }
    }

    nonisolated private func perimer() {
        verrou.lock()
        perime = true
        verrou.unlock()
    }

    /// Le contenu à jour, recalculé seulement si le magasin a été écrit depuis
    /// la dernière lecture.
    ///
    /// Les quatre listes arrivent **non évaluées**, et c'est le fond de
    /// l'affaire : ce sont des `@Query`, et les lire matérialise la requête.
    /// Passées comme valeurs, elles coûtaient les huit cents sorties à chaque
    /// appel — mémoire de calcul ou non, ce qu'on croyait avoir économisé se
    /// repayait à la porte. Mesuré : la mise en cache n'avait rien changé aux
    /// chiffres, ce qui est le signe qu'on avait déplacé le coût sans le
    /// retirer.
    ///
    /// - Parameters:
    ///   - activities: toutes les sorties — un jour où l'on a couru sans rien
    ///     écrire a quand même couru.
    ///   - notedActivities: celles qui ont écrit quelque chose, seules à
    ///     porter un texte.
    func contenu(
        activities: @autoclosure () -> [Activity],
        notedActivities: @autoclosure () -> [Activity],
        mealNotes: @autoclosure () -> [MealNote],
        weights: @autoclosure () -> [WeightEntry]
    ) -> Contenu {
        verrou.lock()
        let aRefaire = perime
        perime = false
        verrou.unlock()
        guard aRefaire else { return contenu }

        let toutes = activities()
        let ecrites = notedActivities()
        let repas = mealNotes()
        let pesees = weights()
        let ailleurs = JournalDaySources.elsewhereNotes(
            activities: ecrites, mealNotes: repas, weights: pesees
        )
        contenu = Contenu(
            elsewhereNotes: ailleurs,
            elsewhereTags: ailleurs.mapValues { textes in
                textes.reduce(into: Set<JournalTag>()) {
                    $0.formUnion(JournalTagScanner.tags(in: $1))
                }
            },
            marks: JournalDaySources.marks(activities: toutes, weights: pesees),
            jours: JournalDaySources.libraryDayKeys(
                activities: toutes, mealNotes: repas, weights: pesees
            )
        )
        return contenu
    }
}
