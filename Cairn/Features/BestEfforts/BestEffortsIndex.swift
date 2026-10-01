import Foundation
import SwiftData
import Observation

/// Les meilleurs efforts de toute la bibliothèque, tenus à jour en fond.
///
/// Un calcul et non une colonne : `Activity` traverse le miroir, et chaque
/// propriété stockée y est une colonne de Supabase. Ce qui se recalcule depuis
/// les séries n'a rien à faire là-bas — et le recalcul est bon marché : les
/// séries distance et temps d'une sortie, une fenêtre glissante par distance.
///
/// Seules les sorties nouvelles ou changées sont relues : chacune garde une
/// empreinte, et une écriture qui ne la touche pas ne coûte qu'une requête sur
/// les lignes, sans ouvrir une seule série.
@MainActor
@Observable
final class BestEffortsIndex {
    /// Les efforts de chaque sortie à pied qui en a, par `uuid`.
    private(set) var efforts: [String: ActivityEfforts] = [:]
    /// Le classement de toute la bibliothèque.
    private(set) var standings = EffortStandings([])
    /// Les podiums de chaque sortie, par `uuid` : ce que lisent les badges.
    private(set) var medals: [String: [EffortMedal]] = [:]
    /// Faux tant que le premier passage n'a pas rendu ses chiffres.
    private(set) var isReady = false

    @ObservationIgnored private var fingerprints: [String: String] = [:]
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let observers = NotificationObservers()

    nonisolated private static let entitesSuivies: Set<String> = [
        Schema.entityName(for: Activity.self),
        Schema.entityName(for: ActivityStreams.self),
    ]

    init() {}

    /// Un premier passage, puis un nouveau après chaque écriture qui touche
    /// les sorties ou leurs séries — regroupées : une synchronisation en
    /// enregistre des dizaines d'affilée.
    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        observers.observe(ModelContext.didSave) { [weak self] notification in
            guard Self.touche(notification) else { return }
            Task { @MainActor in self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Les sorties de `uuids` seulement — les filtres de la barre latérale.
    func standings(among uuids: Set<String>) -> EffortStandings {
        EffortStandings(uuids.lazy.compactMap { self.efforts[$0] })
    }

    nonisolated private static func touche(_ notification: Notification) -> Bool {
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
        guard !identifiants.isEmpty else { return true }
        return identifiants.contains { entitesSuivies.contains($0.entityName) }
    }

    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func refresh() {
        guard let container else { return }
        // Un passage à la fois : celui qui arrive pendant un autre attend son
        // tour, il ne le double pas.
        let previous = task
        let known = fingerprints
        task = Task { [weak self] in
            await previous?.value
            let scan = await Task.detached(priority: .utility) {
                Self.scan(container: container, known: known)
            }.value
            self?.apply(scan)
        }
    }

    private func apply(_ scan: Scan) {
        guard !scan.failed else { return }
        var next: [String: ActivityEfforts] = [:]
        for (uuid, entry) in scan.unchanged {
            if let kept = efforts[uuid] { next[uuid] = ActivityEfforts(uuid: uuid, date: entry, times: kept.times) }
        }
        for computed in scan.computed where !computed.times.isEmpty {
            next[computed.uuid] = computed
        }
        fingerprints = scan.fingerprints
        let standings = EffortStandings(next.values)
        if next != efforts { efforts = next }
        if standings != self.standings {
            self.standings = standings
            medals = standings.medals()
        }
        if !isReady { isReady = true }
    }

    // MARK: - Fond

    struct Scan: Sendable {
        /// Les sorties dont l'empreinte n'a pas bougé : seule la date est
        /// reprise, une sortie déplacée dans le temps change de rang.
        var unchanged: [String: Date] = [:]
        var computed: [ActivityEfforts] = []
        var fingerprints: [String: String] = [:]
        /// La lecture a échoué : rien n'est remplacé, le passage suivant
        /// réessaiera.
        var failed = false
    }

    nonisolated static func scan(container: ModelContainer, known: [String: String]) -> Scan {
        let context = ModelContext(container)
        let sports = BestEfforts.sports.map(\.rawValue)
        var descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { sports.contains($0.sportTypeRaw) }
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.streams]
        guard let activities = Log.maintenance.attempt("sorties à pied pour les records", {
            try context.fetch(descriptor)
        }) else { return Scan(failed: true) }

        var scan = Scan()
        for activity in activities {
            // Le tapis n'a pas de record, comme sur Strava : sa vitesse vient
            // d'un capteur au pied, et une séance du 7 mai 2025 sortait un
            // 400 m en 1:14 qui n'a jamais été couru.
            guard !activity.isTrainer,
                  let streams = activity.streams, streams.pointCount > 1 else { continue }
            let fingerprint = "\(streams.uuid):\(streams.pointCount)"
            scan.fingerprints[activity.uuid] = fingerprint
            if known[activity.uuid] == fingerprint {
                scan.unchanged[activity.uuid] = activity.startDate
                continue
            }
            scan.computed.append(ActivityEfforts(
                uuid: activity.uuid,
                date: activity.startDate,
                times: BestEfforts.compute(streams: streams)
            ))
        }
        return scan
    }
}
