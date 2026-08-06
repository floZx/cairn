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
    var minDurationMinutes: Double?
    var minElevation: Double?
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
        let minDuration = Int((minDurationMinutes ?? 0) * 60)
        let minGain = minElevation ?? 0
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
        let matchesDurationAndElevation = #Predicate<Activity> { activity in
            activity.movingTime >= minDuration && activity.totalElevationGain >= minGain
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
                && matchesDurationAndElevation.evaluate(activity)
                && (!filtersRegion
                    || (latOverlapsRegion.evaluate(activity) && lonOverlapsRegion.evaluate(activity)))
        }
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
        hasher.combine(minDurationMinutes)
        hasher.combine(minElevation)
        hasher.combine(minElevationPerKm)
        hasher.combine(labels)
        hasher.combine(region?.minLat)
        hasher.combine(region?.maxLat)
        hasher.combine(region?.minLon)
        hasher.combine(region?.maxLon)
    }
}
