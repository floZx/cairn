import Foundation
import MapKit
import SwiftData

/// Gathers `TitleIngredients` for an activity being edited.
///
/// Reads the draft rather than the stored activity wherever the editor can
/// change the answer — sport, date, distance, markers — so a sport corrected
/// a second ago is the one the titles speak of.
@available(macOS 26.0, *)
@MainActor
enum TitleIngredientsBuilder {
    static func build(
        activity: Activity, draft: ActivityDraft, library: [Activity]
    ) -> TitleIngredients {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = draft.timeZone
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "fr_FR")
        weekday.timeZone = draft.timeZone
        weekday.dateFormat = "EEEE"

        let track = activity.simplifiedCoordinates
        var ingredients = TitleIngredients(
            sport: draft.sport,
            weekday: weekday.string(from: draft.startDate),
            partOfDay: .init(hour: calendar.component(.hour, from: draft.startDate)),
            distanceKm: draft.distanceKm,
            movingMinutes: Int(draft.movingMinutes.rounded()),
            elevationGain: draft.elevationGain,
            relief: TitleIngredients.relief(
                elevation: draft.elevationGain, distanceKm: draft.distanceKm, sport: draft.sport
            ),
            shape: TitleIngredients.shape(of: track),
            length: TitleIngredients.length(
                distanceKm: draft.distanceKm,
                usualKm: usualDistanceKm(sport: draft.sport, excluding: activity, in: library)
            )
        )
        ingredients.previousOnRoute = SameRouteSection.matches(for: activity, in: library)
            .filter { $0.startDate < activity.startDate }
            .count
        // Not where laps are something else: pool lengths, a walk's or a
        // ski day's automatic splits — 60 lengths read as three repeats.
        let noRepeats: Set<SportType> = [.swim, .walk, .hike, .nordicSki, .alpineSki]
        ingredients.intervals = noRepeats.contains(draft.sport) ? nil : IntervalReader.read(
            activity.laps.sorted { $0.lapIndex < $1.lapIndex }.map {
                LapFigures(
                    distance: $0.distance, movingTime: $0.movingTime,
                    averageHeartrate: $0.averageHeartrate, elevationGain: $0.totalElevationGain
                )
            }
        )
        ingredients.isRace = draft.workoutLabel == .race
        ingredients.isCommute = draft.isCommute
        ingredients.isIndoor = draft.isTrainer
        ingredients.averageHeartrate = activity.averageHeartrate
        return ingredients
    }

    /// The median of the last year's outings in the same sport — a median,
    /// so one marathon doesn't make every run look short. Nil under five
    /// outings, where « usual » would mean nothing.
    static func usualDistanceKm(
        sport: SportType, excluding activity: Activity, in library: [Activity]
    ) -> Double? {
        let yearAgo = Date().addingTimeInterval(-365 * 24 * 3600)
        let distances = library
            .filter {
                $0.sportType == sport && $0.distance > 0 && $0.startDate > yearAgo
                    && $0.persistentModelID != activity.persistentModelID
            }
            .map { $0.distance / 1000 }
            .sorted()
        guard distances.count >= 5 else { return nil }
        return distances[distances.count / 2]
    }

    /// The communes along the way, in the order they are crossed.
    ///
    /// Apple's geocoder names communes well and lieux-dits not at all — a
    /// point by Sanzieux comes back as a street address in Sury-le-Comtal —
    /// so only the commune is kept. One request per sampled point, in turn:
    /// seven requests stay far below MapKit's limit, and a failure only
    /// costs that point.
    static func places(along track: [Coordinate]) async -> [String] {
        var found: [String] = []
        for point in TitleIngredients.samplePoints(of: track) {
            guard !Task.isCancelled,
                  let request = MKReverseGeocodingRequest(
                      location: CLLocation(latitude: point.latitude, longitude: point.longitude)
                  )
            else { continue }
            request.preferredLocale = Locale(identifier: "fr_FR")
            guard let item = try? await request.mapItems.first,
                  let city = item.addressRepresentations?.cityName,
                  !found.contains(city)
            else { continue }
            found.append(city)
        }
        return found
    }
}
