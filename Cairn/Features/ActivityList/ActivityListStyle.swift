import Foundation

/// How the activities are shown.
///
/// Two presentations rather than one improved: the table sorts by any column,
/// packs a screenful of rows and compares figures at a glance; the cards show
/// the shape of the track and the photos. Neither replaces the other, which is
/// why this is a preference and not a redesign.
enum ActivityListStyle: String, CaseIterable, Identifiable, Sendable {
    case table
    case cards

    static let storageKey = "activityListStyle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .table: "Tableau"
        case .cards: "Fiches"
        }
    }

    var symbolName: String {
        switch self {
        case .table: "tablecells"
        case .cards: "rectangle.grid.1x2"
        }
    }
}
