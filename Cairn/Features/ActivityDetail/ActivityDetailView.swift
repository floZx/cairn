import SwiftUI
import SwiftData

struct ActivityDetailView: View {
    let activity: Activity
    var onExpandMap: (() -> Void)?
    @Environment(AppEnvironment.self) private var app

    /// Distance under the cursor in a chart, mirrored on the map as a marker.
    @State private var hoverDistanceKm: Double?
    @AppStorage(MapStyle.storageKey) private var mapStyle: MapStyle = .standard
    @AppStorage(TrackColor.storageKey) private var trackColor: TrackColor = .accent

    /// Cached: the body re-evaluates on every mouse move while a chart is
    /// hovered, and deriving this from the blobs each time made hover pay an
    /// O(n) decode per event.
    private var trackModel: ActivityTrackModel {
        ActivityTrackModelCache.model(for: activity)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // No placeholder when there is no track: a pool swim or a gym
                // session simply has nowhere to be drawn, and a large empty
                // panel announcing that is worse than the map's absence.
                if trackModel.coordinates.count > 1 {
                    ActivityMapView(
                        coordinates: trackModel.coordinates,
                        highlight: hoverDistanceKm.flatMap(trackModel.coordinate(atKilometre:)),
                        style: mapStyle,
                        trackColor: trackColor
                    )
                    .frame(height: 320)
                    .mapChrome(style: $mapStyle) {
                        if let onExpandMap {
                            MapExpandButton(action: onExpandMap)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                }

                statistics

                if !trackModel.series.isEmpty {
                    StreamChartsView(
                        series: trackModel.series, hoverDistanceKm: $hoverDistanceKm
                    )
                }

                if !activity.laps.isEmpty {
                    laps
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
            SportLabel(activity.sportType.displayName, sport: activity.sportType)
                .foregroundStyle(.secondary)
            Text(activity.name).font(.largeTitle.weight(.semibold))
            Text(Format.longDate(activity.startLocalDate))
                .foregroundStyle(.secondary)

            // Said outright, and for every source including Strava. Showing the
            // origin only when it was *not* Strava made the common case silent,
            // so an activity wrongly marked as imported looked no different from
            // a synced one until you noticed the badge that should not be there.
            HStack(spacing: 6) {
                Label(activity.source.displayName, systemImage: activity.source.symbolName)
                    .help(
                        activity.source.isSynced
                            ? "Apportée par la synchronisation Strava, qui continuera de la mettre à jour"
                            : "N'existe que dans ce journal : la synchronisation Strava ne la touchera pas"
                    )
                if let editedAt = activity.editedAt {
                    Label(
                        "Modifiée le \(Format.dateOnly(editedAt))",
                        systemImage: "pencil"
                    )
                    .help(
                        "Champs protégés de la synchro : "
                            + activity.editedFields
                                .map(\.displayName).sorted()
                                .joined(separator: ", ")
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Sits with the title rather than at the foot of the page: the note
            // is what the activity was about, and it arrives a moment after the
            // rest, once the detail endpoint has been fetched.
            if let note = activity.activityDescription?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !note.isEmpty {
                Text(note)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
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
