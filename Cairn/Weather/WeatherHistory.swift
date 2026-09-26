import Foundation

/// The weather at a place and an instant in the past, from Open-Meteo.
///
/// Free, keyless, no account: the only thing that leaves the Mac is the
/// start's coordinates and time. Hourly values, interpolated to the exact
/// minute — on a real outing started at 08:22 this gave 15,5 °C where
/// Strava said 15, 79 % of humidity for 76, and the same south-south-west
/// wind.
struct WeatherHistory: Sendable {
    /// What the hour around the start looked like.
    struct Reading: Sendable, Equatable {
        var temperature: Double
        var apparentTemperature: Double
        var humidity: Double
        var windSpeed: Double
        var windDirection: Double
        var weatherCode: Int
        var cloudCover: Double
        var precipitation: Double
        var isDay: Bool
    }

    enum Failure: LocalizedError, Equatable {
        case http(Int)
        case noData

        var errorDescription: String? {
            switch self {
            case let .http(status): "Open-Meteo a répondu \(status)."
            case .noData: "Open-Meteo n'a pas de météo pour ce moment."
            }
        }
    }

    private static let fields = [
        "temperature_2m", "apparent_temperature", "relative_humidity_2m",
        "wind_speed_10m", "wind_direction_10m", "weather_code", "cloud_cover",
        "precipitation", "is_day",
    ]

    let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func reading(latitude: Double, longitude: Double, at date: Date) async throws -> Reading {
        let (data, response) = try await transport.send(
            URLRequest(url: Self.url(latitude: latitude, longitude: longitude, at: date))
        )
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.http(response.statusCode)
        }
        guard let reading = Self.parse(data, at: date) else { throw Failure.noData }
        return reading
    }

    /// Two services behind one API: the forecasts as they were issued,
    /// hour by hour since 2022 and up to date within the day; before that,
    /// the ERA5 reanalysis, back to 1940 but a few days behind.
    static func url(latitude: Double, longitude: Double, at date: Date) -> URL {
        let recent = date >= Date(timeIntervalSince1970: 1_640_995_200) // 2022-01-01
        var components = URLComponents(
            string: recent
                ? "https://historical-forecast-api.open-meteo.com/v1/forecast"
                : "https://archive-api.open-meteo.com/v1/archive"
        )!
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        // The day before and after too: a start at 00:30 UTC interpolates
        // with the hour before it.
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "start_date", value: day.string(from: date.addingTimeInterval(-86_400))),
            URLQueryItem(name: "end_date", value: day.string(from: date.addingTimeInterval(86_400))),
            URLQueryItem(name: "hourly", value: fields.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]
        return components.url!
    }

    /// The two hours around `date`, blended: linearly for the figures, the
    /// nearer hour for what can't be averaged — a weather code, day or
    /// night, and the wind's direction: a light wind turning from 195° to
    /// 98° averaged to south-south-east at 08:22, where Strava and the
    /// nearer hour both said south-south-west.
    static func parse(_ data: Data, at date: Date) -> Reading? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let times = (hourly["time"] as? [NSNumber])?.map(\.doubleValue),
              !times.isEmpty
        else { return nil }
        func series(_ key: String) -> [Double?] {
            (hourly[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }

        let t = date.timeIntervalSince1970
        let after = times.firstIndex(where: { $0 >= t }) ?? times.count - 1
        let before = times[after] > t && after > 0 ? after - 1 : after
        let span = times[after] - times[before]
        let f = span > 0 ? (t - times[before]) / span : 0
        let nearest = f < 0.5 ? before : after

        func blend(_ key: String) -> Double? {
            let values = series(key)
            guard values.indices.contains(after), let a = values[before], let b = values[after] else {
                return nil
            }
            return a + (b - a) * f
        }
        func pick(_ key: String) -> Double? {
            let values = series(key)
            return values.indices.contains(nearest) ? values[nearest] : nil
        }

        guard let temperature = blend("temperature_2m") else { return nil }
        return Reading(
            temperature: temperature,
            apparentTemperature: blend("apparent_temperature") ?? temperature,
            humidity: blend("relative_humidity_2m") ?? 0,
            windSpeed: blend("wind_speed_10m") ?? 0,
            windDirection: pick("wind_direction_10m") ?? 0,
            weatherCode: Int(pick("weather_code") ?? 0),
            // The sky of the nearer hour, like its code: 23 % at 08:00 and
            // 1 % at 09:00 blended to a clear sky at 08:22, under a morning
            // Strava remembered as « quelques nuages ».
            cloudCover: pick("cloud_cover") ?? 0,
            precipitation: pick("precipitation") ?? 0,
            isDay: (pick("is_day") ?? 1) != 0
        )
    }
}

// MARK: - Saying it

/// How the sky is said and drawn.
///
/// Rain, snow, fog and storms from the WMO code; the sky itself from the
/// cloud cover, which is finer — on the real outing above, the code said
/// « couvert » for an hour whose cover was 23 %, and Strava « quelques
/// nuages ».
struct WeatherSky: Equatable {
    let label: String
    let symbol: String

    init(code: Int, cloudCover: Double, isDay: Bool) {
        switch code {
        case 45, 48: (label, symbol) = ("Brouillard", "cloud.fog")
        case 51...57: (label, symbol) = ("Bruine", "cloud.drizzle")
        case 61, 63, 66: (label, symbol) = ("Pluie", "cloud.rain")
        case 65, 67: (label, symbol) = ("Forte pluie", "cloud.heavyrain")
        case 71...77: (label, symbol) = ("Neige", "cloud.snow")
        case 80...82: (label, symbol) = ("Averses", isDay ? "cloud.sun.rain" : "cloud.moon.rain")
        case 85, 86: (label, symbol) = ("Averses de neige", "cloud.snow")
        case 95...99: (label, symbol) = ("Orage", "cloud.bolt.rain")
        default:
            switch cloudCover {
            case ..<20: (label, symbol) = ("Ciel dégagé", isDay ? "sun.max" : "moon.stars")
            case ..<50: (label, symbol) = ("Quelques nuages", isDay ? "cloud.sun" : "cloud.moon")
            case ..<85: (label, symbol) = ("Nuageux", isDay ? "cloud.sun" : "cloud.moon")
            default: (label, symbol) = ("Couvert", "cloud")
            }
        }
    }

    /// Where the wind comes from, on the French sixteen-point rose: « SSO »,
    /// not Strava's « SSW ».
    static func compass(_ degrees: Double) -> String {
        let points = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO",
        ]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360) / 22.5).rounded()) % 16
        return points[index]
    }
}
