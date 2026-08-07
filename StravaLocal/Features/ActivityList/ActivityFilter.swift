import Foundation
import SwiftData

enum DatePeriod: String, CaseIterable, Sendable, Identifiable {
    case all, last30Days, last90Days, thisYear, lastYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "Toutes les dates"
        case .last30Days: "30 derniers jours"
        case .last90Days: "90 derniers jours"
        case .thisYear: "Cette année"
        case .lastYear: "L'an dernier"
        }
    }

    func startDate(now: Date) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        switch self {
        case .all: return nil
        case .last30Days: return calendar.date(byAdding: .day, value: -30, to: now)
        case .last90Days: return calendar.date(byAdding: .day, value: -90, to: now)
        case .thisYear:
            return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .lastYear:
            guard let thisYear = calendar.date(
                from: calendar.dateComponents([.year], from: now)
            ) else { return nil }
            return calendar.date(byAdding: .year, value: -1, to: thisYear)
        }
    }

    func endDate(now: Date) -> Date? {
        guard case .lastYear = self else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: calendar.dateComponents([.year], from: now))
    }
}

/// The filter state, and its translation into a database predicate.
///
/// Everything expressible in SQL goes into `predicate` — including the
/// geographic pre-filter, thanks to the indexed bounding-box columns. Only the
/// precise "does the track actually enter this region" test happens in memory,
/// on the already-narrowed result.
struct ActivityFilter: Sendable, Equatable {
    var searchText: String = ""
    var sports: Set<SportType> = []
    var period: DatePeriod = .all
    var minDistanceKm: Double?
    var maxDistanceKm: Double?
    var minElevation: Double?
    var maxElevation: Double?
    /// Kept out of `predicate` on purpose: expressing metres-per-kilometre in a
    /// SwiftData predicate needs a division, and this predicate has already had
    /// to be split into sub-expressions to stay inside the type-checker. It is
    /// cheap arithmetic on rows the database has already narrowed.
    var minElevationPerKm: Double?
    /// Also outside `predicate`: one of these labels comes from `workoutType`,
    /// an optional Int, and SwiftData predicates cannot unwrap captured
    /// optionals. An activity must carry *every* selected label.
    var labels: Set<ActivityLabel> = []
    var region: BoundingBox?

    static let none = ActivityFilter()

    var isActive: Bool { self != .none }

    /// How many criteria are narrowing the list.
    var activeCriteriaCount: Int { criteria.count }

    /// What is narrowing the list, in words — nil when nothing is.
    ///
    /// A shortened list with no visible reason is confusing, so this goes beside
    /// the activity count. Long selections are cut short: the point is knowing
    /// that a filter is on and roughly which, not reading the whole set from a
    /// title bar.
    var summary: String? {
        let parts = criteria
        guard !parts.isEmpty else { return nil }
        guard parts.count > 3 else { return parts.joined(separator: " · ") }
        let shown = parts.prefix(3).joined(separator: " · ")
        return "\(shown) · +\(parts.count - 3)"
    }

    /// Each active criterion as a short phrase, in a stable order.
    ///
    /// Sets are walked through an ordered source rather than iterated, so the
    /// same filter always reads the same way.
    private var criteria: [String] {
        var parts: [String] = []
        let text = searchText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { parts.append("« \(text) »") }
        if !sports.isEmpty {
            let names = SportType.allCases.filter(sports.contains).map(\.displayName)
            parts.append(
                names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) sports"
            )
        }
        if period != .all { parts.append(period.displayName) }
        if let minDistanceKm { parts.append("≥ \(Format.typedNumber(minDistanceKm)) km") }
        if let maxDistanceKm { parts.append("≤ \(Format.typedNumber(maxDistanceKm)) km") }
        if let minElevation {
            parts.append("D+ ≥ \(Format.typedNumber(minElevation)) m")
        }
        if let maxElevation {
            parts.append("D+ ≤ \(Format.typedNumber(maxElevation)) m")
        }
        if let minElevationPerKm {
            parts.append("D+/km ≥ \(Format.typedNumber(minElevationPerKm)) m")
        }
        parts.append(
            contentsOf: ActivityLabel.allCases.filter(labels.contains).map(\.displayName)
        )
        if region != nil { parts.append("zone sur la carte") }
        return parts
    }

    func predicate(now: Date = Date()) -> Predicate<Activity> {
        // Sentinel bounds instead of optionals: SwiftData predicates can't
        // unwrap captured optionals, but they compare captured scalars fine.
        let text = searchText.trimmingCharacters(in: .whitespaces)
        let sportValues = sports.map(\.rawValue)
        let filtersSport = !sportValues.isEmpty
        let start = period.startDate(now: now) ?? .distantPast
        let end = period.endDate(now: now) ?? .distantFuture
        let minDistance = (minDistanceKm ?? 0) * 1000
        let maxDistance = (maxDistanceKm ?? .greatestFiniteMagnitude) * 1000
        let minGain = minElevation ?? 0
        let maxGain = maxElevation ?? .greatestFiniteMagnitude
        let box = region ?? .world
        let filtersRegion = region != nil

        // Split into sub-predicates and recombine below: a single conjunction
        // this large defeats the type-checker ("unable to type-check this
        // expression in reasonable time"). Each piece stays small enough to
        // solve quickly; #Predicate supports composing them via `.evaluate`.
        let matchesTextAndSport = #Predicate<Activity> { activity in
            (text.isEmpty || activity.name.localizedStandardContains(text))
                && (!filtersSport || sportValues.contains(activity.sportTypeRaw))
        }
        let matchesPeriod = #Predicate<Activity> { activity in
            activity.startDate >= start && activity.startDate < end
        }
        let matchesDistance = #Predicate<Activity> { activity in
            activity.distance >= minDistance && activity.distance <= maxDistance
        }
        let matchesElevation = #Predicate<Activity> { activity in
            activity.totalElevationGain >= minGain
                && activity.totalElevationGain <= maxGain
        }
        // The region test alone (five chained comparisons) still defeated the
        // type-checker, so it's split once more, latitude and longitude apart;
        // `!filtersRegion || …` is applied in the top-level predicate.
        // Destructured into plain scalars first: the predicate engine cannot
        // translate a key-path access on a captured struct value, so
        // `box.maxLat` inside a `#Predicate` fails to build.
        let boxMinLat = box.minLat
        let boxMaxLat = box.maxLat
        let boxMinLon = box.minLon
        let boxMaxLon = box.maxLon

        let latOverlapsRegion = #Predicate<Activity> { activity in
            activity.hasTrack && activity.minLat <= boxMaxLat && activity.maxLat >= boxMinLat
        }
        let lonOverlapsRegion = #Predicate<Activity> { activity in
            activity.minLon <= boxMaxLon && activity.maxLon >= boxMinLon
        }

        return #Predicate<Activity> { activity in
            matchesTextAndSport.evaluate(activity)
                && matchesPeriod.evaluate(activity)
                && matchesDistance.evaluate(activity)
                && matchesElevation.evaluate(activity)
                && (!filtersRegion
                    || (latOverlapsRegion.evaluate(activity) && lonOverlapsRegion.evaluate(activity)))
        }
    }

    /// Both passes at once, for callers holding activities already in memory.
    ///
    /// The database predicate narrows, then `matchesPrecisely` settles what SQL
    /// could not express. Every in-memory caller needs the pair, and running one
    /// without the other silently over-reports.
    func apply(to activities: [Activity], now: Date = Date()) -> [Activity] {
        let predicate = predicate(now: now)
        return activities.filter { activity in
            ((try? predicate.evaluate(activity)) ?? true) && matchesPrecisely(activity)
        }
    }

    /// The same filter with its date range dropped.
    ///
    /// The statistics view owns its own period — it has to reach into the
    /// preceding one to compare against it, which this filter would have already
    /// removed — while every other criterion still applies.
    var ignoringPeriod: ActivityFilter {
        var copy = self
        copy.period = .all
        return copy
    }

    /// Second pass: bounding boxes can overlap a region a track never enters.
    func matchesPrecisely(_ activity: Activity) -> Bool {
        if !labels.isEmpty {
            guard labels.isSubset(of: Set(activity.labels)) else { return false }
        }
        if let minElevationPerKm {
            // An activity with no distance can't be hilly, so it never passes a
            // climbing-per-kilometre floor.
            guard activity.distance > 0,
                  activity.elevationPerKilometre >= minElevationPerKm
            else { return false }
        }
        guard let region else { return true }
        guard activity.hasTrack else { return false }
        return region.containsAnyPoint(of: activity.simplifiedCoordinates)
    }
}

extension ActivityFilter: Hashable {
    // `BoundingBox` is `Equatable` only, so automatic `Hashable` synthesis
    // isn't available; `RootView` needs `Hashable` to key `.id(effectiveFilter)`
    // and force `ActivityListView` to rebuild its `@Query` on filter changes.
    // Hashing the region's own scalar fields keeps this in sync with `==`
    // without requiring a change to `BoundingBox`.
    func hash(into hasher: inout Hasher) {
        hasher.combine(searchText)
        hasher.combine(sports)
        hasher.combine(period)
        hasher.combine(minDistanceKm)
        hasher.combine(maxDistanceKm)
        hasher.combine(minElevation)
        hasher.combine(maxElevation)
        hasher.combine(minElevationPerKm)
        hasher.combine(labels)
        hasher.combine(region?.minLat)
        hasher.combine(region?.maxLat)
        hasher.combine(region?.minLon)
        hasher.combine(region?.maxLon)
    }
}
