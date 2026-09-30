import Foundation
import SwiftData

/// One day's weight as Garmin Connect reports it.
struct GarminWeighIn: Sendable, Equatable {
    let dateKey: DateKey
    let weightKg: Double

    /// Reads `/weight-service/weight/range`: one summary per day, whose
    /// `latestWeight` is the figure Garmin's own app shows for that day.
    /// Weights travel in grams. `dateWeightList`, the shape of the older
    /// `dateRange` endpoint, is read too, in case the range one moves.
    static func parse(_ json: Any?) -> [GarminWeighIn] {
        guard let root = json as? [String: Any] else { return [] }
        if let summaries = root["dailyWeightSummaries"] as? [[String: Any]] {
            return summaries.compactMap { summary in
                let latest = summary["latestWeight"] as? [String: Any]
                return make(
                    day: summary["summaryDate"] ?? latest?["calendarDate"],
                    grams: latest?["weight"]
                )
            }
        }
        let list = root["dateWeightList"] as? [[String: Any]] ?? []
        // Several weigh-ins a day in this shape: the last one listed wins,
        // as `latestWeight` does in the other.
        var byDay: [String: GarminWeighIn] = [:]
        for item in list {
            if let weighIn = make(day: item["calendarDate"], grams: item["weight"]) {
                byDay[weighIn.dateKey.raw] = weighIn
            }
        }
        return Array(byDay.values)
    }

    private static func make(day: Any?, grams: Any?) -> GarminWeighIn? {
        guard let raw = day as? String,
              let key = DateKey(raw: String(raw.prefix(10))),
              let grams = (grams as? NSNumber)?.doubleValue, grams > 0
        else { return nil }
        // Rounded to the scale's own 0.1 kg: 71 400 g arrives as 71399.99.
        return GarminWeighIn(dateKey: key, weightKg: (grams / 100).rounded() / 10)
    }
}

/// Copies Garmin's weigh-ins into the local `WeightEntry` table, once per
/// launch.
///
/// The first pass reads the whole history a year at a time; after that only
/// the last few days are asked again, which catches a weigh-in corrected on
/// Garmin after the fact. Garmin wins on a day it knows — the scale is the
/// measure — but a note written in Cairn stays. Nothing is ever deleted here.
@MainActor
final class GarminWeightImporter {
    private let client: GarminClient
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?

    /// The Garmin setting: off, nothing is asked of Garmin and the nutrition
    /// screen shows no weight. What was already copied stays in the store.
    static let enabledKey = "garminWeightsEnabled"

    /// The last day a pass reached, so the next launch asks only from there.
    static let syncedThroughKey = "garminWeightsSyncedThrough"
    /// Days asked again on every pass, for late corrections.
    static let overlapDays = 7
    /// How far back the first pass may go, and how many empty years in a row
    /// end it before that.
    static let oldestYear = 2010
    static let emptyYearsToStop = 2

    init(client: GarminClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func start(container: ModelContainer) {
        guard task == nil, defaults.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        task = Task { [weak self] in
            await self?.run(container: container)
            self?.task = nil
        }
    }

    /// Forgets how far the import went, for a new account.
    func reset() {
        defaults.removeObject(forKey: Self.syncedThroughKey)
    }

    private func run(container: ModelContainer) async {
        let today = DateKey(Date())
        let context = ModelContext(container)
        if let raw = defaults.string(forKey: Self.syncedThroughKey),
           let through = DateKey(raw: raw) {
            let from = min(through, today).advanced(by: -Self.overlapDays)
            guard let found = await Log.garmin.attempt("pesées Garmin récentes", {
                try await client.weighIns(from: from, to: today)
            }) else { return }
            store(found, in: context, through: today)
            return
        }

        // The whole history, newest year first, so today's chart fills in
        // before the old years arrive.
        var end = today
        var emptyYears = 0
        let calendar = Calendar.current
        while emptyYears < Self.emptyYearsToStop,
              calendar.component(.year, from: end.date()) >= Self.oldestYear {
            let start = end.advanced(by: -364)
            guard let found = await Log.garmin.attempt("pesées Garmin \(start.raw) → \(end.raw)", {
                try await client.weighIns(from: start, to: end)
            }) else { return }
            emptyYears = found.isEmpty ? emptyYears + 1 : 0
            store(found, in: context, through: nil)
            end = start.advanced(by: -1)
        }
        defaults.set(today.raw, forKey: Self.syncedThroughKey)
    }

    private func store(_ found: [GarminWeighIn], in context: ModelContext, through: DateKey?) {
        guard Log.garmin.attempt("pesées Garmin enregistrées", {
            try Self.merge(found, in: context)
        }) != nil else { return }
        if let through { defaults.set(through.raw, forKey: Self.syncedThroughKey) }
    }

    /// Upserts by day and saves once. A day whose weight is already the same
    /// is left untouched, so a pass that brings nothing new writes nothing —
    /// and sends nothing to the mirror. Returns how many days changed.
    @discardableResult
    static func merge(_ weighIns: [GarminWeighIn], in context: ModelContext) throws -> Int {
        guard !weighIns.isEmpty else { return 0 }
        let keys = weighIns.map(\.dateKey.raw)
        let existing = try context.fetch(FetchDescriptor<WeightEntry>(
            predicate: #Predicate { keys.contains($0.dateKeyRaw) }
        ))
        var byDay = Dictionary(existing.map { ($0.dateKeyRaw, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = 0
        for weighIn in weighIns {
            if let entry = byDay[weighIn.dateKey.raw] {
                guard abs(entry.weightKg - weighIn.weightKg) >= 0.05 else { continue }
                entry.weightKg = weighIn.weightKg
            } else {
                let entry = WeightEntry(dateKey: weighIn.dateKey, weightKg: weighIn.weightKg)
                context.insert(entry)
                byDay[weighIn.dateKey.raw] = entry
            }
            changed += 1
        }
        if changed > 0 { try context.save() }
        return changed
    }
}
