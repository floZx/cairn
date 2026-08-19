import EventKit
import Foundation
import SwiftData

/// Reprendre le plan là où il était : dans un calendrier macOS.
///
/// Une reprise, pas une synchronisation. Le calendrier est la source d'hier ;
/// une fois les séances en base, c'est Cairn qui les détient, sur les deux
/// écrans. Rien ici ne réécrit jamais l'agenda.
enum TrainingCalendarImport {
    /// Un événement d'agenda réduit à ce que l'import en retient.
    ///
    /// Un type à part plutôt qu'un `EKEvent` : EventKit demande une
    /// autorisation et un magasin, donc le tri, le dédoublonnage et la mise en
    /// ordre ne seraient vérifiables qu'en accordant l'accès au calendrier de
    /// la machine qui fait tourner les tests.
    struct Evenement: Equatable {
        var dateKey: DateKey
        var titre: String
        var notes: String = ""
        /// L'instant de départ, pour ranger deux séances d'une même journée.
        var debut: Date = .distantPast
    }

    /// Ce qu'il reste à créer, une fois écarté ce qui existe déjà.
    ///
    /// Le repère est le couple jour + intitulé : c'est ce qu'on voit, et deux
    /// imports du même agenda ne doivent pas doubler le plan. Conséquence
    /// assumée — deux séances homonymes le même jour n'en font qu'une, ce
    /// qu'aucun plan réel ne demande.
    static func aCreer(
        _ evenements: [Evenement], deja existantes: [(jour: String, titre: String)]
    ) -> [Evenement] {
        var vues = Set(existantes.map { $0.jour + "\u{1}" + $0.titre })
        var retenus: [Evenement] = []
        for evenement in evenements.sorted(by: { $0.debut < $1.debut }) {
            let titre = evenement.titre.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !titre.isEmpty else { continue }
            let cle = evenement.dateKey.raw + "\u{1}" + titre
            guard vues.insert(cle).inserted else { continue }
            retenus.append(Evenement(
                dateKey: evenement.dateKey, titre: titre,
                notes: evenement.notes, debut: evenement.debut
            ))
        }
        return retenus
    }

    /// Écrit les séances retenues, en les numérotant par journée.
    @discardableResult
    static func ecrire(
        _ evenements: [Evenement], dans context: ModelContext
    ) throws -> Int {
        var rangs: [String: Int] = [:]
        for evenement in evenements {
            let lu = TrainingImport.lire(evenement.titre)
            let rang = rangs[evenement.dateKey.raw, default: 0]
            rangs[evenement.dateKey.raw] = rang + 1
            let seance = PlannedSession(
                dateKey: evenement.dateKey,
                sportTypeRaw: lu.sport.rawValue,
                title: lu.titre,
                plannedDistance: lu.distance,
                plannedDuration: lu.duree,
                plannedElevation: lu.denivele,
                notes: evenement.notes,
                sortOrder: rang
            )
            context.insert(seance)
        }
        try context.save()
        return evenements.count
    }

    // MARK: - Le calendrier de la machine

    /// Demande l'accès, une fois. Rendu `false` si l'utilisateur refuse — ce
    /// qui n'est pas une erreur : l'import est un service, pas une condition.
    ///
    /// `@MainActor` et non générique : `EKEventStore` n'est pas `Sendable`, et
    /// la vue qui le détient vit sur l'acteur principal. Le marquer ici est
    /// plus honnête que de le faire traverser.
    @MainActor
    static func demanderAcces(_ store: EKEventStore) async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func calendriers(_ store: EKEventStore) -> [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    /// Les événements d'un calendrier, entre deux jours inclus.
    ///
    /// Par tranches d'un an : `predicateForEvents` refuse une plage de plus de
    /// quatre ans, et un plan repris de loin en franchit facilement plusieurs.
    static func evenements(
        de calendrier: EKCalendar, du debut: DateKey, au fin: DateKey,
        dans store: EKEventStore, calendar: Calendar = .current
    ) -> [Evenement] {
        var lus: [Evenement] = []
        var curseur = debut.date(calendar: calendar)
        let terme = fin.advanced(by: 1, calendar: calendar).date(calendar: calendar)
        while curseur < terme {
            let borne = min(
                calendar.date(byAdding: .year, value: 1, to: curseur) ?? terme, terme
            )
            let predicat = store.predicateForEvents(
                withStart: curseur, end: borne, calendars: [calendrier]
            )
            for evenement in store.events(matching: predicat) {
                lus.append(Evenement(
                    dateKey: DateKey(evenement.startDate, calendar: calendar),
                    titre: evenement.title ?? "",
                    notes: evenement.notes ?? "",
                    debut: evenement.startDate
                ))
            }
            curseur = borne
        }
        return lus
    }
}
