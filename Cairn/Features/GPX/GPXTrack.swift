import Foundation

/// One recorded point: where, how high, and when.
///
/// Altitude and time are optional because they genuinely are: a route drawn on
/// a map carries neither, and Cairn should still be able to read it.
struct GPXPoint: Sendable, Equatable {
    var coordinate: Coordinate
    var elevation: Double?
    var time: Date?
}

/// A track read from a GPX file, before it becomes an activity.
struct GPXTrack: Sendable, Equatable {
    var name: String?
    /// The `<type>` the file declares, verbatim. Exporters disagree wildly on
    /// its vocabulary, so the mapping to a `SportType` is a guess made
    /// elsewhere rather than a promise made here.
    var type: String?
    var points: [GPXPoint]

    var coordinates: [Coordinate] { points.map(\.coordinate) }
    var elevations: [Double] { points.compactMap(\.elevation) }
    var times: [Date] { points.compactMap(\.time) }
}

enum GPXError: LocalizedError {
    case unreadable
    case noPoints

    var errorDescription: String? {
        switch self {
        case .unreadable: "Ce fichier n'est pas un GPX lisible."
        case .noPoints: "Ce fichier GPX ne contient aucun point de tracé."
        }
    }
}
