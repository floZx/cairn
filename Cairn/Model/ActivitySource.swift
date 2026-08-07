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

    /// What the delete confirmation dialog says will happen.
    ///
    /// Extracted so a test can pin it down: the two consequences are not the
    /// same — a Strava deletion leaves a tombstone a resync cannot cross, a
    /// local one simply loses the activity — and a future refactor collapsing
    /// this into one text would be a half-truth nothing else would catch.
    var deleteConfirmationMessage: String {
        switch self {
        case .strava:
            "Elle ne reviendra pas lors d'une resynchronisation. "
                + "Les réglages permettent d'annuler cet écart."
        case .manual, .file:
            "Cette activité n'existe que dans le journal : elle sera perdue."
        }
    }
}
