import Foundation

/// Wire-format mirrors of the Strava REST responses.
///
/// Property names keep Strava's snake_case on purpose: no key-conversion
/// strategy to maintain, and every field maps visibly onto the published API
/// docs. Renaming to Swift conventions happens once, in `ImportMapper`.
struct MapDTO: Decodable, Sendable {
    let summary_polyline: String?
}

struct SummaryActivityDTO: Decodable, Sendable {
    let id: Int64
    let name: String
    let sport_type: String
    let start_date: Date
    let start_date_local: Date
    let timezone: String?
    let distance: Double
    let moving_time: Int
    let elapsed_time: Int
    let total_elevation_gain: Double
    let average_speed: Double
    let max_speed: Double
    let average_heartrate: Double?
    let max_heartrate: Double?
    let average_watts: Double?
    let weighted_average_watts: Double?
    let kilojoules: Double?
    let average_cadence: Double?
    let commute: Bool?
    let trainer: Bool?
    let manual: Bool?
    let `private`: Bool?
    let workout_type: Int?
    let kudos_count: Int?
    let achievement_count: Int?
    let pr_count: Int?
    let athlete_count: Int?
    let start_latlng: [Double]?
    let end_latlng: [Double]?
    let gear_id: String?
    let map: MapDTO?
}

struct LapDTO: Decodable, Sendable {
    let id: Int64
    let name: String?
    let lap_index: Int
    let distance: Double
    let moving_time: Int
    let elapsed_time: Int
    let total_elevation_gain: Double?
    let average_speed: Double?
    let max_speed: Double?
    let average_heartrate: Double?
    let average_cadence: Double?
    let start_index: Int?
    let end_index: Int?
}

struct DetailActivityDTO: Decodable, Sendable {
    let id: Int64
    let description: String?
    let calories: Double?
    let device_name: String?
    let laps: [LapDTO]?
    let photos: PhotosSummaryDTO?
}

/// What the documented detail endpoint says about photos: a count, and the
/// primary one. There is no documented way to list the others.
struct PhotosSummaryDTO: Decodable, Sendable {
    let count: Int?
    let primary: PhotoDTO?
}

/// One photo, from either source.
///
/// Every field is optional because the two endpoints disagree about which they
/// send, and the undocumented one is under no obligation to keep sending any of
/// them. A photo missing everything but a URL is still a photo worth keeping.
struct PhotoDTO: Decodable, Sendable {
    let unique_id: String?
    /// Pixel size to address. Keys are strings even though they are numbers.
    let urls: [String: String]?
    let caption: String?
    let created_at: Date?
    let created_at_local: Date?
}

struct StreamDTO<Element: Decodable & Sendable>: Decodable, Sendable {
    let data: [Element]
}

/// Result of `key_by_type=true`: one keyed object per requested stream.
struct StreamSetDTO: Decodable, Sendable {
    let latlng: StreamDTO<[Double]>?
    let distance: StreamDTO<Double>?
    let altitude: StreamDTO<Double>?
    let time: StreamDTO<Int>?
    let heartrate: StreamDTO<Double>?
    let cadence: StreamDTO<Double>?
    let watts: StreamDTO<Double>?
    let velocity_smooth: StreamDTO<Double>?
    let temp: StreamDTO<Double>?
    let grade_smooth: StreamDTO<Double>?
    let moving: StreamDTO<Bool>?
}

struct AthleteDTO: Decodable, Sendable {
    let id: Int64
    let firstname: String?
    let lastname: String?
    let city: String?
    let country: String?
    let profile: String?
    let weight: Double?
}

struct TokenResponseDTO: Decodable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int
    let athlete: AthleteDTO?
}

struct GearDTO: Decodable, Sendable {
    let id: String
    let name: String
    let brand_name: String?
    let model_name: String?
    let distance: Double?
}

enum StravaJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
