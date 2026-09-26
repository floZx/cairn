import Foundation
import SwiftData

/// The weather at an activity's start, fetched once from Open-Meteo's
/// archive and kept.
///
/// A model of its own rather than fields on `Activity`, keyed by the
/// activity's uuid: it doesn't conform to `MirrorRow`, so it stays on this
/// Mac — a figure any device can fetch again for free has no business
/// in Supabase — and `Activity` itself, which the mirror does carry, isn't
/// touched when it arrives.
@Model
final class ActivityWeather {
    #Unique<ActivityWeather>([\.activityUUID])

    var activityUUID: String = ""
    var fetchedAt: Date = Date()

    /// °C, at 2 m.
    var temperature: Double = 0
    /// °C, what it felt like: wind and humidity included.
    var apparentTemperature: Double = 0
    /// %, relative.
    var humidity: Double = 0
    /// km/h, at 10 m.
    var windSpeed: Double = 0
    /// Degrees the wind comes *from*, 0 for north.
    var windDirection: Double = 0
    /// WMO code: 0–3 sky, 45–48 fog, 51–67 drizzle and rain, 71–77 snow,
    /// 80–86 showers, 95–99 thunderstorm.
    var weatherCode: Int = 0
    /// %, of the sky.
    var cloudCover: Double = 0
    /// mm in the hour.
    var precipitation: Double = 0
    var isDay: Bool = true

    init(activityUUID: String) {
        self.activityUUID = activityUUID
    }
}
