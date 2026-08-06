import SwiftUI
import SwiftData

struct ActivityDetailView: View {
    let activity: Activity
    @Environment(AppEnvironment.self) private var app

    private var trackCoordinates: [Coordinate] {
        // Full-resolution track when the streams are in; the simplified one is
        // a perfectly good stand-in until then.
        let detailed = activity.streams?.coordinates ?? []
        return detailed.isEmpty ? activity.simplifiedCoordinates : detailed
    }

    private var series: [StreamSeries] {
        StreamSeriesBuilder.series(
            from: activity.streams, totalDistance: activity.distance
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // No placeholder when there is no track: a pool swim or a gym
                // session simply has nowhere to be drawn, and a large empty
                // panel announcing that is worse than the map's absence.
                if trackCoordinates.count > 1 {
                    ActivityMapView(coordinates: trackCoordinates)
                        .frame(height: 320)
                        .clipShape(.rect(cornerRadius: 8))
                }

                statistics

                if !series.isEmpty {
                    StreamChartsView(series: series)
                }

                if !activity.laps.isEmpty {
                    laps
                }

                if let description = activity.activityDescription,
                   !description.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.headline)
                        Text(description)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(activity.name)
        .task(id: activity.stravaID) {
            app.loadDetail(stravaID: activity.stravaID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(activity.sportType.displayName, systemImage: activity.sportType.symbolName)
                .foregroundStyle(.secondary)
            Text(activity.name).font(.largeTitle.weight(.semibold))
            Text(Format.longDate(activity.startLocalDate))
                .foregroundStyle(.secondary)
        }
    }

    private var statistics: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
            spacing: 16
        ) {
            StatTile("Distance", Format.distance(activity.distance))
            StatTile("Temps en mouvement", Format.duration(activity.movingTime))
            StatTile("Temps total", Format.duration(activity.elapsedTime))
            StatTile("Dénivelé +", Format.elevation(activity.totalElevationGain))
            StatTile(
                "Vitesse moyenne",
                Format.speed(activity.averageSpeed, sport: activity.sportType)
            )
            StatTile(
                "Vitesse max",
                Format.speed(activity.maxSpeed, sport: activity.sportType)
            )
            StatTile("FC moyenne", Format.heartrate(activity.averageHeartrate))
            StatTile("FC max", Format.heartrate(activity.maxHeartrate))
            StatTile("Puissance moyenne", Format.power(activity.averageWatts))
            StatTile("Puissance normalisée", Format.power(activity.weightedAverageWatts))
            StatTile("Cadence", Format.cadence(activity.averageCadence))
            if let gear = activity.gear {
                StatTile("Matériel", gear.name)
            }
        }
    }

    private var laps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tours").font(.headline)
            Table(activity.laps.sorted { $0.lapIndex < $1.lapIndex }) {
                TableColumn("#") { Text("\($0.lapIndex)") }.width(30)
                TableColumn("Distance") { Text(Format.distance($0.distance)) }
                TableColumn("Temps") { Text(Format.duration($0.movingTime)) }
                TableColumn("D+") { Text(Format.elevation($0.totalElevationGain)) }
                TableColumn("Vitesse") {
                    Text(Format.speed($0.averageSpeed, sport: activity.sportType))
                }
                TableColumn("FC") { Text(Format.heartrate($0.averageHeartrate)) }
            }
            .frame(height: min(CGFloat(activity.laps.count) * 28 + 28, 240))
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
    }
}
