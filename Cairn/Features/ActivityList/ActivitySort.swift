import Foundation

/// What the list is sorted by, for the presentation that has no column headers.
///
/// Drives the very same `sortOrder` the table's headers write to: two orders
/// for two presentations of one list would reshuffle everything on each switch.
enum ActivitySort: String, CaseIterable, Identifiable, Sendable {
    case date
    case name
    case distance
    case duration
    case elevation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .date: "Date"
        case .name: "Nom"
        case .distance: "Distance"
        case .duration: "Durée"
        case .elevation: "Dénivelé"
        }
    }

    /// Which way round the field reads first.
    ///
    /// A name wants A→Z; a date, a distance or a climb want the biggest and the
    /// most recent first, because that is the one being looked for.
    var startsAscending: Bool { self == .name }

    func comparators(ascending: Bool) -> [KeyPathComparator<Activity>] {
        let order: SortOrder = ascending ? .forward : .reverse
        switch self {
        case .date: return [KeyPathComparator(\Activity.startLocalDate, order: order)]
        case .name: return [KeyPathComparator(\Activity.name, order: order)]
        case .distance: return [KeyPathComparator(\Activity.distance, order: order)]
        case .duration: return [KeyPathComparator(\Activity.movingTime, order: order)]
        case .elevation:
            return [KeyPathComparator(\Activity.totalElevationGain, order: order)]
        }
    }

    /// Which field an existing order is on, or nil when it is one the menu does
    /// not offer — a column the table has and this does not.
    static func current(_ order: [KeyPathComparator<Activity>]) -> ActivitySort? {
        guard let keyPath = order.first?.keyPath else { return nil }
        return allCases.first {
            $0.comparators(ascending: true).first?.keyPath == keyPath
        }
    }

    static func isAscending(_ order: [KeyPathComparator<Activity>]) -> Bool {
        order.first?.order == .forward
    }
}
