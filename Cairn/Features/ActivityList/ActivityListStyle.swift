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

    /// The other one. Two cases, so a toggle is the whole vocabulary a shortcut
    /// needs — a picker would want a key each.
    var toggled: ActivityListStyle {
        self == .table ? .cards : .table
    }

    var symbolName: String {
        switch self {
        case .table: "tablecells"
        case .cards: "rectangle.grid.1x2"
        }
    }
}

/// What stands at the head of a card: the shape of the outing, its sport in a
/// round badge — the way Mail heads a message with a face — or nothing, for a
/// list of words and figures alone.
enum ActivityCardThumbnail: String, CaseIterable, Identifiable, Sendable {
    case trace
    case traceAvatar
    case avatar
    case avatarMono
    case none

    static let storageKey = "activityCardThumbnail"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trace: "Aperçu de la trace"
        case .traceAvatar: "Trace en pastille"
        case .avatar: "Pastille du sport"
        case .avatarMono: "Pastille monochrome"
        case .none: "Aucune"
        }
    }
}
