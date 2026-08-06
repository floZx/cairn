import Foundation

/// The markers Strava lets you put on an activity.
///
/// Two sources: plain booleans on the summary (commute, trainer, manual,
/// private), and `workout_type`, whose codes differ by sport — a run uses
/// 1/2/3 for race, long run and workout, while a ride uses 11/12 for race and
/// workout. Reading a ride's `1` as "race" would be wrong, hence the explicit
/// mapping rather than arithmetic.
enum ActivityLabel: String, CaseIterable, Sendable, Identifiable, Codable {
    case race
    case longRun
    case workout
    case commute
    case trainer
    case manual
    case isPrivate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .race: "Compétition"
        case .longRun: "Sortie longue"
        case .workout: "Entraînement"
        case .commute: "Trajet"
        case .trainer: "Home trainer"
        case .manual: "Manuelle"
        case .isPrivate: "Privée"
        }
    }

    /// Short enough for a narrow table column.
    var shortName: String {
        switch self {
        case .race: "Compét."
        case .longRun: "Longue"
        case .workout: "Entraîn."
        case .commute: "Trajet"
        case .trainer: "Trainer"
        case .manual: "Manuelle"
        case .isPrivate: "Privée"
        }
    }

    var symbolName: String {
        switch self {
        case .race: "flag.checkered"
        case .longRun: "arrow.right.to.line"
        case .workout: "stopwatch"
        case .commute: "arrow.triangle.swap"
        case .trainer: "house"
        case .manual: "hand.raised"
        case .isPrivate: "lock"
        }
    }

    /// The workout type this label corresponds to, if any.
    ///
    /// Strava sends 0/10 for "no particular type", which is the absence of a
    /// label rather than a label of its own.
    static func fromWorkoutType(_ code: Int?) -> ActivityLabel? {
        switch code {
        // Runs 0-3, rides 10-12, and a third family in the 30s seen in real
        // data (walks and hikes): each family reserves its round number for
        // "no particular type", then +1 for a race and +2 for a workout.
        case 1, 11, 31: .race
        case 2: .longRun
        case 3, 12, 32: .workout
        default: nil
        }
    }
}
