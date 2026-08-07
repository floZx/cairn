import Foundation
import SwiftData

/// A plausible but invented library, for screenshots and for trying the app out.
///
/// Exists so the README can show what the app looks like without publishing
/// anybody's training history: activity names and the places you train are
/// personal data, and a screenshot of a real library gives away both.
///
/// Two safeguards. It only runs when `STRAVALOCAL_DEMO` is set, and when it does
/// the whole app opens a *different* store file — see `AppModelContainer.make`.
/// The real library is never opened, so it cannot be written to.
///
/// Deterministic: a fixed seed rather than `random()`, so the same launch gives
/// the same library and a screenshot can be retaken identically.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["STRAVALOCAL_DEMO"] != nil
    }

    /// Fills an empty demo store, and does nothing on one already filled.
    static func populateIfNeeded(_ context: ModelContext, now: Date = Date()) throws {
        guard isEnabled else { return }
        let existing = try context.fetch(FetchDescriptor<Activity>())
        guard existing.isEmpty else { return }

        let athlete = Athlete(stravaID: 424_242)
        athlete.firstName = "Camille"
        athlete.lastName = "Durand"
        athlete.city = "Le Puy-en-Velay"
        athlete.country = "France"
        context.insert(athlete)

        for outing in library(now: now) {
            context.insert(outing)
        }
        try context.save()
    }

    // MARK: - Generation

    /// Eighteen months of training, so the twelve-month window has a full year
    /// behind it to compare against.
    private static let monthsOfHistory = 18

    /// Invented ground in the Monts du Forez: a real landscape makes the
    /// topographic backgrounds and the elevation profiles look like themselves,
    /// while the routes over it are entirely made up.
    private static let home = Coordinate(latitude: 45.4275, longitude: 3.9410)

    private struct Template {
        let sport: SportType
        let names: [String]
        /// Kilometres, low to high.
        let distance: ClosedRange<Double>
        /// Metres of climbing per kilometre.
        let climbPerKilometre: ClosedRange<Double>
        /// Metres per second.
        let speed: ClosedRange<Double>
        let heartRate: ClosedRange<Double>
        /// Roughly how many of these per month.
        let perMonth: Int
        let hasTrack: Bool
    }

    private static let templates: [Template] = [
        Template(
            sport: .trailRun,
            names: [
                "Sortie longue au Forez", "Boucle des Hautes Chaumes",
                "Montée au Pierre-sur-Haute", "Trail du matin",
                "Crêtes et sous-bois", "Reconnaissance du parcours",
            ],
            distance: 12...38, climbPerKilometre: 25...45, speed: 2.1...2.9,
            heartRate: 138...162, perMonth: 5, hasTrack: true
        ),
        Template(
            sport: .run,
            names: [
                "Footing de récupération", "Fractionné sur piste",
                "Sortie au fil de la Loire", "Seuil 3 × 8 min",
            ],
            distance: 6...16, climbPerKilometre: 4...12, speed: 2.8...3.6,
            heartRate: 142...168, perMonth: 4, hasTrack: true
        ),
        Template(
            sport: .ride,
            names: [
                "Col de la Loge", "Boucle du barrage", "Sortie club du dimanche",
                "Vers les gorges",
            ],
            distance: 35...110, climbPerKilometre: 10...22, speed: 6.5...8.5,
            heartRate: 124...148, perMonth: 3, hasTrack: true
        ),
        Template(
            sport: .hike,
            names: ["Randonnée en famille", "Cascade et plateau"],
            distance: 8...18, climbPerKilometre: 20...35, speed: 1.1...1.5,
            heartRate: 104...122, perMonth: 1, hasTrack: true
        ),
        Template(
            // No track and no distance: the app has to stay honest about those,
            // and a demo library that only contains tidy outdoor outings would
            // hide how it handles them.
            sport: .workout,
            names: ["Renforcement", "Gainage et mobilité", "Séance salle"],
            distance: 0...0, climbPerKilometre: 0...0, speed: 0...0,
            heartRate: 96...118, perMonth: 4, hasTrack: false
        ),
    ]

    /// The invented library itself, separate from inserting it so the generation
    /// can be tested without a store.
    ///
    /// The seed is fixed, so two calls with the same `now` give the same library
    /// — a screenshot can be retaken identically.
    static func library(now: Date) -> [Activity] {
        var generator = SeededGenerator(seed: 20_260_807)
        let calendar = Calendar(identifier: .gregorian)
        var activities: [Activity] = []
        var stravaID: Int64 = 9_000_000_000

        for monthsBack in (0..<monthsOfHistory).reversed() {
            guard let month = calendar.date(
                byAdding: .month, value: -monthsBack, to: now
            ) else { continue }

            for template in templates {
                // A season, not a metronome: fewer long outings in winter, which
                // is what makes the monthly chart worth looking at.
                let month0 = calendar.component(.month, from: month)
                let winter = month0 <= 2 || month0 == 12
                let count = max(1, template.perMonth - (winter ? 2 : 0))

                for _ in 0..<count {
                    let day = generator.int(in: 1...27)
                    let hour = generator.int(in: 7...18)
                    guard let date = calendar.date(
                        bySetting: .day, value: day, of: month
                    ).flatMap({
                        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0)
                    }), date <= now else { continue }

                    stravaID += 1
                    activities.append(
                        make(
                            template: template, stravaID: stravaID, date: date,
                            using: &generator
                        )
                    )
                }
            }
        }
        return activities
    }

    private static func make(
        template: Template,
        stravaID: Int64,
        date: Date,
        using generator: inout SeededGenerator
    ) -> Activity {
        let activity = Activity(
            stravaID: stravaID,
            name: template.names[generator.int(in: 0...(template.names.count - 1))],
            sportType: template.sport
        )
        activity.startDate = date
        activity.startLocalDate = date

        let kilometres = generator.double(in: template.distance)
        activity.distance = kilometres * 1000
        activity.totalElevationGain =
            kilometres * generator.double(in: template.climbPerKilometre)
        activity.averageSpeed = generator.double(in: template.speed)
        activity.maxSpeed = activity.averageSpeed * generator.double(in: 1.3...1.8)
        activity.movingTime = activity.averageSpeed > 0
            ? Int(activity.distance / activity.averageSpeed)
            : Int(generator.double(in: 2400...4200))
        activity.elapsedTime = activity.movingTime
            + generator.int(in: 60...900)
        activity.averageHeartrate = generator.double(in: template.heartRate)
        activity.maxHeartrate = (activity.averageHeartrate ?? 140)
            + generator.double(in: 10...28)
        activity.calories = Double(activity.movingTime) / 3600 * 620
        activity.kudosCount = generator.int(in: 0...24)

        guard template.hasTrack else { return activity }

        let track = loop(
            kilometres: kilometres, elevationGain: activity.totalElevationGain,
            using: &generator
        )
        // Through the model's own setters, so the demo library is indexed and
        // simplified exactly like an imported one — the geographic search and the
        // global map read those, not the streams.
        if let box = BoundingBox(coordinates: track.coordinates) {
            activity.apply(boundingBox: box)
        }
        activity.apply(
            simplifiedCoordinates: Simplify.douglasPeucker(track.coordinates)
        )
        let streams = ActivityStreams()
        streams.pointCount = track.coordinates.count
        streams.latlng = TrackBlob.encode(coordinates: track.coordinates)
        streams.altitude = TrackBlob.encode(scalars: track.altitudes.map(Float.init))
        streams.distance = TrackBlob.encode(scalars: track.distances.map(Float.init))
        streams.heartrate = TrackBlob.encode(
            scalars: track.distances.map { _ in
                Float(generator.double(in: template.heartRate))
            }
        )
        streams.activity = activity
        activity.streams = streams
        activity.detailFetchedAt = date
        return activity
    }

    private struct Loop {
        let coordinates: [Coordinate]
        let altitudes: [Double]
        let distances: [Double]
    }

    /// A wandering closed loop rather than a circle: a perfect ring reads as
    /// obviously fake on a map, and the whole point is a believable screenshot.
    private static func loop(
        kilometres: Double, elevationGain: Double, using generator: inout SeededGenerator
    ) -> Loop {
        let points = max(60, min(400, Int(kilometres * 12)))
        // Degrees of latitude for the loop's radius, from its circumference.
        let radius = (kilometres * 1000 / (2 * .pi)) / 111_320
        let wobbleSeeds = (0..<5).map { _ in generator.double(in: 0.7...1.3) }

        var coordinates: [Coordinate] = []
        var altitudes: [Double] = []

        for index in 0..<points {
            let t = Double(index) / Double(points) * 2 * .pi
            // A few harmonics make the outline meander the way a valley path does.
            let wobble = wobbleSeeds.enumerated().reduce(1.0) { partial, pair in
                partial + 0.16 * sin(Double(pair.offset + 2) * t) * (pair.element - 1)
            }
            let latitude = home.latitude + radius * wobble * cos(t)
            let longitude = home.longitude
                + radius * wobble * sin(t) / cos(home.latitude * .pi / 180)
            let point = Coordinate(latitude: latitude, longitude: longitude)

            coordinates.append(point)
            // Two climbs and two descents over the loop, around the plateau's
            // real altitude, scaled to the gain the summary claims.
            let profile = (1 - cos(2 * t)) / 2
            altitudes.append(880 + profile * elevationGain / 2)
        }

        // Closed: back to the start, as a loop is.
        if let first = coordinates.first {
            coordinates.append(first)
            altitudes.append(altitudes.first ?? 880)
        }
        // Measured from the geometry rather than accumulated by hand, so the
        // distance stream agrees with the track the app will draw.
        return Loop(
            coordinates: coordinates,
            altitudes: altitudes,
            distances: DistanceAxis.cumulativeMetres(along: coordinates)
        )
    }
}

/// A tiny reproducible generator.
///
/// `SystemRandomNumberGenerator` would give a different library on every launch,
/// so a screenshot could never be retaken. This is xorshift — not for anything
/// that needs real randomness, only for making the same invented data twice.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Zero is a fixed point of xorshift, so it would return nothing but zero.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        return Double.random(in: range, using: &self)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        return Int.random(in: range, using: &self)
    }
}
