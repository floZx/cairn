import Foundation

// MARK: - What Garmin says

struct GarminActivity: Sendable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let description: String
    let typeKey: String?
    let start: Date?
    let distance: Double?
    let duration: Double?

    /// Accepts both an item of the activity list and the activity endpoint:
    /// the second tucks its figures under `summaryDTO` and its type under
    /// `activityTypeDTO`.
    init?(json: [String: Any]) {
        guard let id = (json["activityId"] as? NSNumber)?.int64Value else { return nil }
        let summary = json["summaryDTO"] as? [String: Any] ?? [:]
        func pick(_ key: String) -> Any? { json[key] ?? summary[key] }
        let type = (json["activityType"] ?? json["activityTypeDTO"]) as? [String: Any]

        self.id = id
        name = json["activityName"] as? String ?? ""
        description = json["description"] as? String ?? ""
        typeKey = type?["typeKey"] as? String
        start = (pick("startTimeGMT") as? String).flatMap(Self.parseGMT)
        distance = (pick("distance") as? NSNumber)?.doubleValue
        duration = (pick("duration") as? NSNumber)?.doubleValue
    }

    init(
        id: Int64, name: String, description: String = "", typeKey: String?,
        start: Date?, distance: Double?, duration: Double?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.typeKey = typeKey
        self.start = start
        self.distance = distance
        self.duration = duration
    }

    /// `2024-05-01 07:12:33` in the list, `2024-05-01T07:12:33.0` in the
    /// detail — both in UTC, neither saying so.
    static func parseGMT(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let trimmed = text.replacingOccurrences(of: "T", with: " ")
            .split(separator: ".").first.map(String.init) ?? text
        return formatter.date(from: trimmed)
    }
}

struct GarminGear: Sendable, Equatable, Identifiable {
    let uuid: String
    let name: String
    let model: String
    /// `shoes`, `bike`, `other`…
    let type: String
    let isRetired: Bool

    var id: String { uuid }

    init?(json: [String: Any]) {
        guard let uuid = json["uuid"] as? String else { return nil }
        self.uuid = uuid
        let model = json["customMakeModel"] as? String ?? ""
        name = (json["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (model.isEmpty ? "Sans nom" : model)
        self.model = model
        type = (json["gearTypeName"] as? String ?? "").lowercased()
        isRetired = (json["gearStatusName"] as? String ?? "").lowercased() == "retired"
    }

    init(uuid: String, name: String, model: String = "", type: String, isRetired: Bool = false) {
        self.uuid = uuid
        self.name = name
        self.model = model
        self.type = type
        self.isRetired = isRetired
    }
}

struct GarminActivityType: Sendable, Equatable {
    let typeID: Int
    let typeKey: String
    let parentTypeID: Int

    init?(json: [String: Any]) {
        guard let id = (json["typeId"] as? NSNumber)?.intValue,
              let key = json["typeKey"] as? String
        else { return nil }
        typeID = id
        typeKey = key
        parentTypeID = (json["parentTypeId"] as? NSNumber)?.intValue ?? 0
    }
}

// MARK: - What Cairn says

/// The part of an activity the comparison reads, copied off the model so it
/// can cross into the client's actor.
struct GarminSource: Sendable, Equatable {
    var name: String
    var description: String
    var sport: SportType
    var isTrainer: Bool
    var start: Date
    var distance: Double
    var duration: Double
    var gear: GearSnapshot?

    struct GearSnapshot: Sendable, Equatable {
        var name: String
        var brand: String?
        var model: String?
        var isBike: Bool
    }

    init(
        name: String, description: String, sport: SportType, isTrainer: Bool,
        start: Date, distance: Double, duration: Double, gear: GearSnapshot?
    ) {
        self.name = name
        self.description = description
        self.sport = sport
        self.isTrainer = isTrainer
        self.start = start
        self.distance = distance
        self.duration = duration
        self.gear = gear
    }

    @MainActor
    init(_ activity: Activity) {
        self.init(
            name: activity.name,
            // Garmin shows its description as typed: the note goes there
            // without its Markdown, as it reads on screen.
            description: MarkdownPlainText.render(activity.activityDescription ?? ""),
            sport: activity.sportType,
            isTrainer: activity.isTrainer,
            start: activity.startDate,
            distance: activity.distance,
            duration: Double(activity.elapsedTime),
            gear: activity.gear.map {
                GearSnapshot(
                    name: $0.name, brand: $0.brandName, model: $0.modelName, isBike: $0.isBike
                )
            }
        )
    }
}

// MARK: - The comparison

/// What to write on Garmin for it to say what Cairn says. Only the fields
/// that differ are set.
struct GarminProposal: Sendable, Equatable {
    enum Field: String, CaseIterable, Sendable, Identifiable {
        case name, type, description, gear
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .name: "Titre"
            case .type: "Type"
            case .description: "Description"
            case .gear: "Matériel"
            }
        }
    }

    struct Change: Sendable, Equatable, Identifiable {
        let field: Field
        let current: String
        let proposed: String
        var id: Field { field }
    }

    var name: String?
    var typeKey: String?
    var description: String?
    var gearUUIDs: [String]?
    /// Said rather than silently skipped: without it the sheet would claim
    /// Garmin is up to date while the shoes are not.
    var unmatchedGearName: String?
    var changes: [Change] = []

    var isEmpty: Bool { changes.isEmpty }
}

/// Everything here is pure, so the rules garmin-revisited tested carry over
/// with their tests.
enum GarminMatching {
    /// Two recordings of one outing start at the same second when one was
    /// synced from the other; the margin is for activities typed in by hand.
    static let maxStartGap: TimeInterval = 20 * 60

    /// From 0 to 1, or nil when the two can't be the same outing.
    static func score(_ source: GarminSource, _ garmin: GarminActivity) -> Double? {
        guard let start = garmin.start else { return nil }
        let gap = abs(start.timeIntervalSince(source.start))
        guard gap <= maxStartGap else { return nil }
        var score = 1 - 0.6 * (gap / maxStartGap)
        if let d = relativeGap(source.distance, garmin.distance) {
            score -= 0.25 * min(d * 4, 1)
        }
        if let d = relativeGap(source.duration, garmin.duration) {
            score -= 0.15 * min(d * 4, 1)
        }
        return max(score, 0)
    }

    static func bestMatch(
        for source: GarminSource, among candidates: [GarminActivity]
    ) -> GarminActivity? {
        candidates
            .compactMap { c in score(source, c).map { (c, $0) } }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }

    private static func relativeGap(_ a: Double, _ b: Double?) -> Double? {
        guard a > 0, let b, b > 0 else { return nil }
        return abs(a - b) / max(a, b)
    }

    /// Cairn's sport → the Garmin type to propose, and the Garmin types
    /// already taken as saying the same. A run left as « running » on
    /// Garmin isn't worth correcting to anything, and a gym session Garmin
    /// calls « yoga » knows better than Cairn's single « Renforcement ».
    private static func types(
        for sport: SportType, isTrainer: Bool
    ) -> (proposed: String, equivalents: Set<String>)? {
        switch sport {
        case .ride where isTrainer:
            ("indoor_cycling", ["indoor_cycling", "virtual_ride"])
        case .ride:
            ("road_biking", [
                "cycling", "road_biking", "gravel_cycling", "mountain_biking", "cyclocross",
                "recumbent_cycling", "track_cycling", "bmx", "indoor_cycling", "virtual_ride",
                "e_bike_fitness", "e_bike_mountain", "bike_commuting",
            ])
        case .mountainBikeRide:
            ("mountain_biking", ["mountain_biking", "e_bike_mountain", "downhill_biking", "enduro_mtb"])
        case .gravelRide:
            ("gravel_cycling", ["gravel_cycling", "cyclocross"])
        case .eBikeRide:
            ("e_bike_fitness", ["e_bike_fitness", "e_bike_mountain"])
        case .run where isTrainer:
            ("treadmill_running", ["treadmill_running", "indoor_running", "virtual_run"])
        case .run:
            ("running", [
                "running", "street_running", "track_running", "treadmill_running",
                "indoor_running", "trail_running", "ultra_run", "virtual_run", "obstacle_run",
            ])
        case .trailRun:
            ("trail_running", ["trail_running", "ultra_run"])
        case .walk:
            ("walking", ["walking", "casual_walking", "speed_walking", "hiking"])
        case .hike:
            ("hiking", ["hiking", "mountaineering"])
        case .swim:
            ("lap_swimming", ["lap_swimming", "open_water_swimming", "swimming"])
        case .nordicSki:
            ("cross_country_skiing_ws", [
                "cross_country_skiing_ws", "skate_skiing_ws", "cross_country_classic_skiing",
                "backcountry_skiing", "backcountry_skiing_snowboarding_ws",
            ])
        case .alpineSki:
            ("resort_skiing_snowboarding_ws", [
                "resort_skiing_snowboarding_ws", "resort_skiing", "resort_snowboarding",
                "backcountry_skiing",
            ])
        case .rowing:
            ("rowing", [
                "rowing", "indoor_rowing", "kayaking", "kayaking_v2",
                "stand_up_paddleboarding", "stand_up_paddleboarding_v2",
            ])
        case .workout:
            ("strength_training", [
                "strength_training", "fitness_equipment", "hiit", "cardio_training",
                "indoor_cardio", "elliptical", "stair_climbing", "indoor_rowing",
                "yoga", "pilates", "breathwork",
            ])
        case .other:
            nil
        }
    }

    static func proposedType(for source: GarminSource, current: String?) -> String? {
        guard let (proposed, equivalents) = types(for: source.sport, isTrainer: source.isTrainer),
              !equivalents.contains(current ?? "")
        else { return nil }
        return proposed
    }

    /// Garmin has one text field; Cairn's description already carries the
    /// Strava private note after it. Nothing is proposed when that text is
    /// already somewhere in Garmin's: what was added there stays.
    static func proposedDescription(for source: GarminSource, current: String) -> String? {
        let text = source.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !current.contains(text) else { return nil }
        return text
    }

    /// The Garmin gear whose name best matches Cairn's, or nil below half
    /// the words in common. Names are what the two services share: Strava's
    /// gear ids mean nothing to Garmin.
    static func matchingGear(
        for gear: GarminSource.GearSnapshot, in catalog: [GarminGear]
    ) -> GarminGear? {
        let wanted = normalized(gear.name)
        guard !wanted.isEmpty else { return nil }
        let wantedWords = Set(wanted.split(separator: " "))
        var best: (GarminGear, Double)?
        for candidate in catalog {
            let name = normalized("\(candidate.name) \(candidate.model)")
            guard !name.isEmpty else { continue }
            let words = Set(name.split(separator: " "))
            var score = Double(wantedWords.intersection(words).count)
                / Double(wantedWords.union(words).count)
            if name.contains(wanted) || normalized(candidate.name) == wanted {
                score = max(score, 0.9)
            }
            if (candidate.type == "bike") == gear.isBike { score += 0.05 }
            if !candidate.isRetired { score += 0.01 }
            if score > best?.1 ?? 0 { best = (candidate, score) }
        }
        guard let best, best.1 >= 0.5 else { return nil }
        return best.0
    }

    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func proposal(
        for source: GarminSource,
        garmin: GarminActivity,
        currentGear: [GarminGear],
        catalog: [GarminGear]
    ) -> GarminProposal {
        var result = GarminProposal()

        let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != garmin.name.trimmingCharacters(in: .whitespacesAndNewlines) {
            result.name = name
            result.changes.append(.init(field: .name, current: garmin.name, proposed: name))
        }

        if let type = proposedType(for: source, current: garmin.typeKey) {
            result.typeKey = type
            result.changes.append(.init(
                field: .type, current: displayType(garmin.typeKey), proposed: displayType(type)
            ))
        }

        if let description = proposedDescription(for: source, current: garmin.description) {
            result.description = description
            result.changes.append(.init(
                field: .description, current: garmin.description, proposed: description
            ))
        }

        if let gear = source.gear {
            if let target = matchingGear(for: gear, in: catalog) {
                if !currentGear.contains(where: { $0.uuid == target.uuid }) {
                    // Replaces gear of the same kind — one pair of shoes for
                    // another — and leaves the rest, a heart-rate strap say.
                    let kept = currentGear.filter { $0.type != target.type }
                    result.gearUUIDs = kept.map(\.uuid) + [target.uuid]
                    result.changes.append(.init(
                        field: .gear,
                        current: currentGear.map(\.name).joined(separator: ", "),
                        proposed: (kept + [target]).map(\.name).joined(separator: ", ")
                    ))
                }
            } else {
                result.unmatchedGearName = gear.name
            }
        }

        return result
    }

    /// `road_biking` → « road biking »: Garmin's keys are English and there
    /// is no table of their French names to borrow.
    static func displayType(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "—" }
        return key.replacingOccurrences(of: "_v2", with: "")
            .replacingOccurrences(of: "_ws", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }
}

extension GarminSource {
    /// What was sent, in a form cheap to compare: the fields Garmin receives,
    /// and nothing it doesn't. A new title or pair of shoes in Cairn changes
    /// it, and the activity reads as not synced again; a new heart-rate
    /// chart doesn't.
    var signature: String {
        [
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            sport.rawValue,
            isTrainer ? "trainer" : "",
            description.trimmingCharacters(in: .whitespacesAndNewlines),
            gear?.name ?? "",
        ].joined(separator: "\u{1F}")
    }
}

/// One activity side by side on the two services.
struct GarminComparison: Sendable, Equatable {
    let activity: GarminActivity
    let proposal: GarminProposal
    let currentGear: [GarminGear]
}

extension GarminClient {
    /// Finds the activity on Garmin and works out what differs, or nil when
    /// no Garmin activity starts close enough. Reads only.
    func compare(_ source: GarminSource) async throws -> GarminComparison? {
        let day: TimeInterval = 24 * 3600
        let candidates = try await activities(
            from: source.start.addingTimeInterval(-day),
            to: source.start.addingTimeInterval(day)
        )
        guard let match = GarminMatching.bestMatch(for: source, among: candidates) else {
            return nil
        }
        // The list may leave the description out; the activity itself
        // never does.
        let detail = try await activity(id: match.id)
        let currentGear = try await gear(forActivity: match.id)
        let catalog = source.gear == nil ? [] : try await allGear()
        return GarminComparison(
            activity: detail,
            proposal: GarminMatching.proposal(
                for: source, garmin: detail, currentGear: currentGear, catalog: catalog
            ),
            currentGear: currentGear
        )
    }
}
