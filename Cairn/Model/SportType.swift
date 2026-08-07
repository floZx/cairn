import Foundation

/// The sports we surface in the sidebar. Strava has more values than this;
/// anything unrecognised lands in `.other` rather than polluting the UI.
enum SportType: String, Codable, CaseIterable, Sendable, Identifiable {
    case ride, mountainBikeRide, gravelRide, eBikeRide
    case run, trailRun, walk, hike
    case swim, nordicSki, alpineSki, rowing, workout, other

    var id: String { rawValue }

    init(stravaValue: String) {
        switch stravaValue {
        case "Ride": self = .ride
        case "MountainBikeRide": self = .mountainBikeRide
        case "GravelRide": self = .gravelRide
        case "EBikeRide", "EMountainBikeRide": self = .eBikeRide
        case "Run": self = .run
        case "TrailRun": self = .trailRun
        case "Walk": self = .walk
        case "Hike": self = .hike
        case "Swim": self = .swim
        case "NordicSki", "BackcountrySki": self = .nordicSki
        case "AlpineSki", "Snowboard": self = .alpineSki
        case "Rowing", "Kayaking", "Canoeing": self = .rowing
        case "Workout", "WeightTraining", "Crossfit", "Yoga": self = .workout
        default: self = .other
        }
    }

    var displayName: String {
        switch self {
        case .ride: "Vélo"
        case .mountainBikeRide: "VTT"
        case .gravelRide: "Gravel"
        case .eBikeRide: "Vélo électrique"
        case .run: "Course"
        case .trailRun: "Trail"
        case .walk: "Marche"
        case .hike: "Randonnée"
        case .swim: "Natation"
        case .nordicSki: "Ski de fond"
        case .alpineSki: "Ski alpin"
        case .rowing: "Aviron"
        case .workout: "Renforcement"
        case .other: "Autre"
        }
    }

    /// SF Symbols only — no bundled art, so the app follows system appearance.
    var symbolName: String {
        switch self {
        // All four bikes share `bicycle`: SF Symbols has nothing for a mountain
        // or gravel bike, and `bicycle.circle` was the same drawing in a ring —
        // it read as a badge rather than as a different sport. The colour is
        // what tells them apart now.
        case .ride, .eBikeRide, .mountainBikeRide, .gravelRide: "bicycle"
        case .run, .trailRun: "figure.run"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .swim: "figure.pool.swim"
        case .nordicSki: "figure.skiing.crosscountry"
        case .alpineSki: "figure.skiing.downhill"
        case .rowing: "figure.rowing"
        case .workout: "figure.strengthtraining.traditional"
        case .other: "sparkles"
        }
    }
}
