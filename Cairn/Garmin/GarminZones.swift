import Foundation
import SwiftData

/// An activity's zones as Garmin returns them: five lower bounds and five
/// durations per kind, zone 1 first.
struct GarminZones: Equatable, Sendable {
    var heartRate: Zones?
    var power: Zones?

    struct Zones: Equatable, Sendable {
        var floors: [Double]
        var seconds: [Double]
    }

    init(heartRate: Zones?, power: Zones?) {
        self.heartRate = heartRate
        self.power = power
    }

    /// `[{zoneNumber, secsInZone, zoneLowBoundary}]`, one entry per zone, in
    /// whatever order — sorted here. An empty or missing list is no zones:
    /// an outing without a heart-rate strap, a run without power.
    init(heartRateJSON: Any?, powerJSON: Any?) {
        heartRate = Self.parse(heartRateJSON)
        power = Self.parse(powerJSON)
    }

    static func parse(_ json: Any?) -> Zones? {
        let entries = (json as? [[String: Any]] ?? []).compactMap { entry -> (Int, Double, Double)? in
            guard let number = (entry["zoneNumber"] as? NSNumber)?.intValue,
                  let floor = (entry["zoneLowBoundary"] as? NSNumber)?.doubleValue
            else { return nil }
            let seconds = (entry["secsInZone"] as? NSNumber)?.doubleValue ?? 0
            return (number, floor, seconds)
        }
        .sorted { $0.0 < $1.0 }
        guard !entries.isEmpty, entries.contains(where: { $0.2 > 0 }) else { return nil }
        return Zones(floors: entries.map(\.1), seconds: entries.map(\.2))
    }
}

/// Copies each activity's zones from Garmin, once.
///
/// Two ways in. An activity opened in the pane is looked up at once. And the
/// library behind it is filled in the background, a week of outings at a
/// time, gently: one list per week, two small calls per outing, a pause
/// between each — Garmin's API is not documented, and nothing here should
/// look like a crawl. A failure stops the pass until the next launch; what
/// was found is kept, and `zonesCheckedAt` is what lets it resume.
@MainActor
final class GarminZonesFetcher {
    private let client: GarminClient
    private var inFlight: Set<String> = []
    private var backfillTask: Task<Void, Never>?

    init(client: GarminClient) {
        self.client = client
    }

    /// Le premier jour de la montre Garmin. Avant, les sorties sont arrivées
    /// chez Garmin par un import depuis Strava, et Garmin les a toutes
    /// recalculées d'un coup avec les zones du jour de l'import : seize mois
    /// aux mêmes bornes à un battement près, mesuré. Ce ne sont pas celles de
    /// l'époque — tout ce que ces zones ont pour elles —, donc rien avant.
    static let firstWatchDay: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    }()

    /// Whether an activity is worth asking about: something with a heart
    /// rate or a power reading, old enough for Garmin to have it, and
    /// recorded by the watch.
    static func needsZones(_ activity: Activity, now: Date = Date()) -> Bool {
        activity.zonesCheckedAt == nil
            && activity.startDate >= firstWatchDay
            && (activity.averageHeartrate != nil || activity.averageWatts != nil)
            && activity.startDate < now.addingTimeInterval(-3600)
    }

    /// The pane's own lookup, for the activity on screen.
    func fetchIfNeeded(_ activity: Activity, in context: ModelContext) async {
        guard Self.needsZones(activity), !inFlight.contains(activity.uuid) else { return }
        inFlight.insert(activity.uuid)
        defer { inFlight.remove(activity.uuid) }
        let source = GarminSource(activity)
        let day: TimeInterval = 24 * 3600
        guard let candidates = try? await client.activities(
            from: source.start.addingTimeInterval(-day), to: source.start.addingTimeInterval(day)
        ) else { return }
        await apply(to: activity, candidates: candidates, in: context)
    }

    /// Fills the library in, newest first. Started once per launch.
    func startBackfill(container: ModelContainer) {
        guard backfillTask == nil else { return }
        backfillTask = Task { [weak self] in
            // Not in the launch's first seconds: the sync and the mirror come first.
            try? await Task.sleep(for: .seconds(30))
            await self?.backfill(container: container)
        }
    }

    /// Efface les zones récupérées avant `firstWatchDay` — celles de l'import,
    /// d'avant que la règle existe. En un seul enregistrement ; sans effet une
    /// fois fait.
    static func clearImportedZones(in context: ModelContext) {
        let limite = firstWatchDay
        guard let anciennes = try? context.fetch(FetchDescriptor<Activity>(
            predicate: #Predicate { $0.startDate < limite }
        )) else { return }
        var changed = false
        for activity in anciennes where activity.hrZoneFloors != nil || activity.powerZoneFloors != nil {
            activity.hrZoneFloors = nil
            activity.hrZoneSeconds = nil
            activity.powerZoneFloors = nil
            activity.powerZoneSeconds = nil
            changed = true
        }
        if changed { try? context.save() }
    }

    private func backfill(container: ModelContainer) async {
        let context = ModelContext(container)
        Self.clearImportedZones(in: context)
        let now = Date()
        guard let all = try? context.fetch(
            FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        ) else { return }
        let pending = all.filter { Self.needsZones($0, now: now) }
        let calendar = Calendar(identifier: .iso8601)
        // Grouped by week, so one list call answers for all of a week's outings.
        let weeks = Dictionary(grouping: pending) {
            calendar.dateInterval(of: .weekOfYear, for: $0.startDate)?.start ?? $0.startDate
        }
        // Enregistré par paquets, jamais sortie par sortie : chaque
        // enregistrement fait relire la liste des sorties et redessiner le
        // volet, et un tous les deux secondes faisait saccader le défilement
        // pendant tout le remplissage — signalé. Une fois par paquet de 25,
        // soit à peu près une par minute ; un départ en cours de paquet ne
        // perd que ce paquet, redemandé au lancement suivant.
        var unsaved = 0
        defer { if unsaved > 0 { try? context.save() } }
        for weekStart in weeks.keys.sorted(by: >) {
            if Task.isCancelled { return }
            let day: TimeInterval = 24 * 3600
            guard let candidates = try? await client.activities(
                from: weekStart.addingTimeInterval(-day),
                to: weekStart.addingTimeInterval(8 * day),
                limit: 100
            ) else { return }
            for activity in weeks[weekStart] ?? [] {
                if Task.isCancelled { return }
                guard await apply(to: activity, candidates: candidates, in: context, saving: false)
                else { return }
                unsaved += 1
                if unsaved >= Self.backfillBatch {
                    try? context.save()
                    unsaved = 0
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    static let backfillBatch = 25

    /// Matches, fetches, stores. False when Garmin answered with an error —
    /// the caller stops there rather than insisting.
    @discardableResult
    private func apply(
        to activity: Activity, candidates: [GarminActivity], in context: ModelContext,
        saving: Bool = true
    ) async -> Bool {
        guard let match = GarminMatching.bestMatch(for: GarminSource(activity), among: candidates) else {
            // Not on Garmin — before the watch, or recorded without it. Noted,
            // so it is not asked again.
            activity.zonesCheckedAt = Date()
            if saving { try? context.save() }
            return true
        }
        guard let zones = try? await client.zones(activityID: match.id) else { return false }
        activity.hrZoneFloors = zones.heartRate?.floors
        activity.hrZoneSeconds = zones.heartRate?.seconds
        activity.powerZoneFloors = zones.power?.floors
        activity.powerZoneSeconds = zones.power?.seconds
        activity.zonesCheckedAt = Date()
        if saving { try? context.save() }
        return true
    }
}
