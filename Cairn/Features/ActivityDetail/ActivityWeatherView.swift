import SwiftUI
import SwiftData

/// The weather at the start, in the corner of the activity's header — the
/// block Strava shows, fed from Open-Meteo instead.
///
/// Fetched the first time the activity is opened and stored, so every later
/// opening reads it from disk. Nothing at all for an indoor session or an
/// outing without a position: the weather outside a gym says nothing about
/// the session.
struct ActivityWeatherView: View {
    let activity: Activity

    @Environment(\.modelContext) private var modelContext
    @State private var weather: ActivityWeather?

    var body: some View {
        // A `VStack`, not a `Group`: a group hands its modifiers to its
        // children, and before the weather is known it has none — the task
        // that fetches it was never attached, and nothing ever showed.
        VStack {
            if let weather {
                block(weather)
            }
        }
        .task(id: activity.uuid) { await load() }
    }

    /// The gear row's card, a second one beside it: the sky on the first
    /// line, the figures under it.
    private func block(_ w: ActivityWeather) -> some View {
        let sky = WeatherSky(code: w.weatherCode, cloudCover: w.cloudCover, isDay: w.isDay)
        var figures = [
            Self.degrees(w.temperature) + ", ressenti " + Self.degrees(w.apparentTemperature),
            "\(Int(w.humidity.rounded())) %",
            "vent \(Int(w.windSpeed.rounded())) km/h \(WeatherSky.compass(w.windDirection))",
        ]
        if w.precipitation >= 0.1 {
            figures.append(
                String(format: "%.1f mm/h", w.precipitation).replacingOccurrences(of: ".", with: ",")
            )
        }
        return HStack(spacing: 10) {
            Image(systemName: sky.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(sky.label).fontWeight(.medium)
                Text(figures.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .help("Météo au départ, d'après Open-Meteo")
    }

    static func degrees(_ celsius: Double) -> String {
        "\(Int(celsius.rounded())) °C"
    }

    /// Reads what is stored, or asks Open-Meteo once and stores it.
    private func load() async {
        let uuid = activity.uuid
        weather = nil
        var descriptor = FetchDescriptor<ActivityWeather>(
            predicate: #Predicate { $0.activityUUID == uuid }
        )
        descriptor.fetchLimit = 1
        if let stored = try? modelContext.fetch(descriptor).first {
            weather = stored
            return
        }
        guard let place = Self.startPoint(of: activity),
              !activity.isTrainer,
              // Only once it has happened, with an hour's margin: the archive
              // fills in behind the clock.
              activity.startDate < Date().addingTimeInterval(-3600)
        else { return }

        // A failure shows nothing and is tried again at the next opening:
        // the network, not the outing, is what's missing.
        guard let reading = try? await WeatherHistory().reading(
            latitude: place.latitude, longitude: place.longitude, at: activity.startDate
        ), !Task.isCancelled, activity.uuid == uuid else { return }

        let stored = ActivityWeather(activityUUID: uuid)
        stored.temperature = reading.temperature
        stored.apparentTemperature = reading.apparentTemperature
        stored.humidity = reading.humidity
        stored.windSpeed = reading.windSpeed
        stored.windDirection = reading.windDirection
        stored.weatherCode = reading.weatherCode
        stored.cloudCover = reading.cloudCover
        stored.precipitation = reading.precipitation
        stored.isDay = reading.isDay
        modelContext.insert(stored)
        do {
            try modelContext.save()
            weather = stored
        } catch {
            modelContext.delete(stored)
        }
    }

    /// Strava's start point, or the track's first when only that is known.
    static func startPoint(of activity: Activity) -> Coordinate? {
        if let latitude = activity.startLatitude, let longitude = activity.startLongitude {
            return Coordinate(latitude: latitude, longitude: longitude)
        }
        return activity.simplifiedCoordinates.first
    }
}
