import SwiftUI
import SwiftData

struct ActivityDetailView: View {
    let activity: Activity
    var onExpandMap: (() -> Void)?
    /// Opens the editor. The notes section calls it, which is what turns an
    /// empty journal entry into an invitation rather than a blank.
    var onEdit: (() -> Void)?
    /// Jumps to another activity — the « même parcours » rows use it, so a
    /// past effort on this course is one click away.
    var onSelectActivity: ((PersistentIdentifier) -> Void)?
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
                // Lit by the sport's own colour, so opening an activity says
                // what kind it is before a word is read. A wider blur than the
                // charts get: this block is the tallest thing on the page, and
                // the same radius on it would read as a coloured panel.
                header
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) { sportWatermark }
                    .ambientGlow(
                        activity.sportType.color, cornerRadius: 16, blurRadius: 80
                    )

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

                // Above the figures: a photo says what an outing was in a way no
                // number does, and it arrives with the detail fetch anyway.
                ActivityPhotosStrip(activityUUID: activity.uuid)

                notes

                statistics

                SameRouteSection(activity: activity, onSelect: onSelectActivity)

                if !trackModel.series.isEmpty {
                    StreamChartsView(
                        series: trackModel.series, hoverDistanceKm: $hoverDistanceKm
                    )
                } else if let message = Self.missingChartsMessage(
                    hasStreams: activity.streams != nil,
                    isSynced: activity.source.isSynced
                ) {
                    Label(message, systemImage: "chart.xyaxis.line")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !activity.laps.isEmpty {
                    laps
                }
            }
            .padding()
        }
        // The sport's light on the frosted pane behind the content: the window
        // material can only blend the desktop, so on a dark wallpaper it has
        // nothing to catch and the pane stays grey whatever the outing.
        .sportWash(activity.sportType.color, strength: SportWashStrength.detail)
        .navigationTitle(activity.name)
        .task(id: activity.stravaID) {
            app.loadDetail(stravaID: activity.stravaID)
        }
    }

    /// Why there are no charts, or nil when there are.
    ///
    /// Said out loud because the two reasons look identical when the pane simply
    /// omits them: an activity whose streams are still queued behind a thousand
    /// others is indistinguishable from a ride that recorded neither altitude
    /// nor heart rate. Phase B drains at 200 requests a quarter hour, so the
    /// wait is measured in days on a first import.
    static func missingChartsMessage(hasStreams: Bool, isSynced: Bool) -> String? {
        if hasStreams {
            // The streams arrived and carry nothing to plot: a pool swim, a gym
            // session, a watch with no barometer and no strap.
            return "Cette activité n'a pas de données d'altitude ni de fréquence cardiaque."
        }
        return isSynced
            ? "Les courbes ne sont pas encore téléchargées. Elles arrivent — laissez cette activité ouverte un instant."
            : "Cette activité n'a pas de courbes : elle ne vient pas de Strava."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SportLabel(activity.sportType.displayName, sport: activity.sportType)
                .foregroundStyle(.secondary)
            Text(activity.name).font(.largeTitle.weight(.semibold))
            Text(Format.longDate(activity.startLocalDate))
                .foregroundStyle(.secondary)

            if !headerLabels.isEmpty {
                FlowLayout {
                    ForEach(headerLabels) { label in
                        ActivityLabelChip(label: label)
                    }
                }
                .padding(.top, 2)
            }

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

        }
    }

    /// The markers worth a chip here.
    ///
    /// `manual` drops out when the source line below already says "Saisie
    /// manuelle" — the same fact twice, two lines apart. It stays for an
    /// activity synced from Strava, where the source reads "Strava" and the
    /// marker is the only thing saying it was typed in rather than recorded.
    private var headerLabels: [ActivityLabel] {
        activity.labels.filter { label in
            !(label == .manual && activity.source == .manual)
        }
    }

    /// The sport's own symbol, very large and very faint, filling the space the
    /// title leaves to its right.
    ///
    /// A watermark and not a second icon: the same glyph is already above the
    /// title at reading size, so repeating it solid would add no information and
    /// compete with the name of the activity. Faint, it only carries the colour.
    private var sportWatermark: some View {
        Image(systemName: activity.sportType.symbolName)
            .font(.system(size: 96))
            .foregroundStyle(activity.sportType.color)
            .opacity(0.12)
            // Never a scrollbar's width of glyph hanging off the pane: the
            // header is as narrow as the user cares to drag it.
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The note, or an invitation to write one.
    ///
    /// Shown even when empty, which is the whole point: an activity with no note
    /// used to display nothing at all, so nothing ever suggested writing one. A
    /// journal is only kept if it asks to be.
    private var notes: some View {
        let note = activity.activityDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Notes").font(.headline)
                Spacer()
                if !note.isEmpty, onEdit != nil {
                    Button("Modifier", action: { onEdit?() })
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            if note.isEmpty {
                Button {
                    onEdit?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Écrire une note")
                            Text("Sensations, météo, matériel, ce que vous retiendrez.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(onEdit == nil)
            } else {
                MarkdownText(markdown: note)
                    .textSelection(.enabled)
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
