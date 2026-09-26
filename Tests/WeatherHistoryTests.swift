import Testing
import Foundation
@testable import Cairn

@Suite("Météo au départ")
struct WeatherHistoryTests {
    /// « Battue citoyenne », le 5 septembre 2026 : 08:00 et 09:00 à Sury-le-
    /// Comtal (06:00 et 07:00 UTC), tels qu'Open-Meteo les a rendus.
    private let eight = 1_788_588_000.0 // 2026-09-05 06:00 UTC
    private func response() -> Data {
        let json: [String: Any] = [
            "hourly": [
                "time": [eight, eight + 3600],
                "temperature_2m": [14.1, 17.8],
                "apparent_temperature": [14.0, 18.0],
                "relative_humidity_2m": [86, 68],
                "wind_speed_10m": [4.1, 2.5],
                "wind_direction_10m": [195, 98],
                "weather_code": [3, 0],
                "cloud_cover": [23, 1],
                "precipitation": [0.0, 0.0],
                "is_day": [1, 1],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test("à 08:22, la météo se lit entre 8 h et 9 h")
    func interpolatesToTheMinute() throws {
        let start = Date(timeIntervalSince1970: eight + 22 * 60)
        let reading = try #require(WeatherHistory.parse(response(), at: start))
        // Strava, ce matin-là : 15 °C, ressenti 16, 76 %, vent 2,5 km/h SSW.
        #expect(abs(reading.temperature - 15.46) < 0.01)
        #expect(Int(reading.humidity.rounded()) == 79)
        #expect(reading.weatherCode == 3)
        let sky = WeatherSky(code: reading.weatherCode, cloudCover: reading.cloudCover, isDay: reading.isDay)
        #expect(sky.label == "Quelques nuages")
        #expect(WeatherSky.compass(reading.windDirection) == "SSO")
    }

    @Test("un départ hors des heures rendues prend la plus proche")
    func clampsOutsideTheSeries() throws {
        let late = Date(timeIntervalSince1970: eight + 5 * 3600)
        let reading = try #require(WeatherHistory.parse(response(), at: late))
        #expect(reading.temperature == 17.8)
    }

    @Test("depuis 2022 les prévisions archivées, avant la réanalyse")
    func picksTheService() {
        let recent = WeatherHistory.url(latitude: 45.537, longitude: 4.186, at: Date(timeIntervalSince1970: eight))
        #expect(recent.host == "historical-forecast-api.open-meteo.com")
        #expect(recent.query?.contains("start_date=2026-09-04") == true)
        #expect(recent.query?.contains("end_date=2026-09-06") == true)
        #expect(recent.query?.contains("timeformat=unixtime") == true)

        let old = WeatherHistory.url(latitude: 45.537, longitude: 4.186, at: Date(timeIntervalSince1970: 1_560_150_000))
        #expect(old.host == "archive-api.open-meteo.com")
    }

    @Test("le ciel se dit d'après la couverture, la pluie d'après le code")
    func sky() {
        #expect(WeatherSky(code: 3, cloudCover: 23, isDay: true).label == "Quelques nuages")
        #expect(WeatherSky(code: 0, cloudCover: 5, isDay: false).symbol == "moon.stars")
        #expect(WeatherSky(code: 3, cloudCover: 95, isDay: true).label == "Couvert")
        #expect(WeatherSky(code: 63, cloudCover: 100, isDay: true).label == "Pluie")
        #expect(WeatherSky(code: 95, cloudCover: 100, isDay: true).symbol == "cloud.bolt.rain")
    }

    @Test("la rose des vents est française")
    func compass() {
        #expect(WeatherSky.compass(0) == "N")
        #expect(WeatherSky.compass(202.5) == "SSO")
        #expect(WeatherSky.compass(270) == "O")
        #expect(WeatherSky.compass(355) == "N")
        #expect(WeatherSky.compass(-10) == "N")
    }

    @Test("une réponse sans données ne donne rien")
    func emptyResponse() {
        #expect(WeatherHistory.parse(Data("{}".utf8), at: Date()) == nil)
    }
}
