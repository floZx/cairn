import Foundation

/// The markers Strava lets you put on an activity.
///
/// Two sources: plain booleans on the summary (commute, trainer, manual,
/// private), and `workout_type`, whose codes differ by sport — a run uses
/// 1/2/3 for race, long run and workout, while a ride uses 11/12 for race and
/// workout. Reading a ride's `1` as "race" would be wrong, hence the explicit
/// mapping rather than arithmetic.
enum ActivityLabel: String, CaseIterable, Sendable, Identifiable, Codable {
    /// Purely local, and the only label that is neither Strava's nor derived
    /// from it. Being one of these gets it the badge in the list and the filter
    /// toggle in the sidebar for free.
    case favorite
    case race
    case longRun
    case workout
    case commute
    case trainer
    case manual
    case isPrivate

    var id: String { rawValue }

    /// The three the user can actually choose between.
    ///
    /// `commute` and `trainer` are plain toggles in the editor, and `manual` and
    /// `isPrivate` describe where an activity came from rather than what it was
    /// — nothing the user should be able to claim by hand.
    static let workoutTypes: [ActivityLabel] = [.race, .longRun, .workout]

    var displayName: String {
        switch self {
        case .favorite: "Favori"
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
        case .favorite: "Favori"
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
        case .favorite: "star.fill"
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
    /// Strava only carries this field when a type was actually chosen on the
    /// activity. Otherwise it either sends the family's round number — 0, 10,
    /// 30 — or omits the field entirely; both mean "no particular type" and so
    /// yield no label. In one real library of 840 activities, 230 carried a
    /// round number and 460 had nothing at all, interleaved within the same
    /// sport and period.
    static func fromWorkoutType(_ code: Int?) -> ActivityLabel? {
        switch code {
        // Runs use 0-3, rides 10-12, and gym sessions 30-32. Each family
        // reserves its round number for "no particular type", then +1 for a
        // race and +2 for a workout.
        case 1, 11, 31: .race
        case 2: .longRun
        case 3, 12, 32: .workout
        default: nil
        }
    }
}
