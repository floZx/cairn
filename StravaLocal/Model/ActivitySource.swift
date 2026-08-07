import Foundation

/// Where an activity came from.
///
/// The sync only ever touches what it brought itself; anything entered here or
/// read from a file is the user's, whatever Strava may later say about a
/// coincidentally similar outing.
enum ActivitySource: String, CaseIterable, Sendable {
    case strava
    case manual
    case file

    var displayName: String {
        switch self {
        case .strava: "Strava"
        case .manual: "Saisie manuelle"
        case .file: "Fichier importé"
        }
    }

    /// Whether a Strava sync may update this activity at all.
    var isSynced: Bool { self == .strava }
}
