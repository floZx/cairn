import Foundation

/// A field the user may edit, and therefore one the sync must not overwrite.
///
/// An enum rather than free strings because the raw values are persisted in
/// `Activity.editedFields`: a typo would compile, protect nothing, and show up
/// only as an edit silently overwritten at the next sync.
enum ActivityField: String, CaseIterable, Sendable {
    case name
    case sportType
    case startDate
    case distance
    case movingTime
    case totalElevationGain
    case notes
    case isCommute
    case isTrainer
    case workoutLabel

    var displayName: String {
        switch self {
        case .name: "Nom"
        case .sportType: "Sport"
        case .startDate: "Date"
        case .distance: "Distance"
        case .movingTime: "Durée"
        case .totalElevationGain: "Dénivelé positif"
        case .notes: "Notes"
        case .isCommute: "Domicile-travail"
        case .isTrainer: "Home-trainer"
        case .workoutLabel: "Type de séance"
        }
    }
}
