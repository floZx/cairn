import SwiftUI
import SwiftData

struct ActivityDetailView: View {
    /// The size an activity's note is read at, here and in the editor's
    /// preview — the same text in the same context, so one value for both.
    ///
    /// A point above the system size. The note sits among figures and charts
    /// rather than filling a pane, so it stays well under the journal's 15;
    /// but at the system 13 it read as one more label in a column of labels,
    /// when it is the only prose on the screen.
    static let noteSize: CGFloat = 14

    let activity: Activity
    var onExpandMap: (() -> Void)?
    /// Opens the editor. The notes section calls it, which is what turns an
    /// empty journal entry into an invitation rather than a blank.
    var onEdit: (() -> Void)?
    /// Jumps to another activity — the « même parcours » rows use it, so a
    /// past effort on this course is one click away.
    var onSelectActivity: ((PersistentIdentifier) -> Void)?
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modelContext) private var modelContext

    /// Reading or writing the note, and what is being written.
    ///
    /// The journal's pattern, brought here for the same reason it was adopted
    /// there: one re-reads an outing far more often than one writes about it,
    /// so the pane opens rendered — and writing costs one click rather than a
    /// link, a sheet and a form with eight other fields in it.
    @State private var isEditingNote = false
    /// Held here while it is being typed, exactly as the journal's pane holds
    /// its own: bound straight to the model, every keystroke would be a write
    /// and a re-read, and `TextEditor` loses its selection to a value replaced
    /// from outside.
    @State private var noteDraft = ""
    @FocusState private var noteFocused: Bool
    /// The pending write, so the note reaches the store a moment after the
    /// typing stops rather than at every letter.
    @State private var noteSaveTask: Task<Void, Never>?
    /// Said out loud under the editor: a note that failed to save while the
    /// screen goes on showing it is the silent loss this project exists to
    /// prevent.
    @State private var noteFailure: String?

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
            // No sport line above the title: the watermark behind the header
            // is the same glyph at ten times the size, and the wash over the
            // whole pane is the same colour. Three ways of saying "trail"
            // before the name of the outing is read.
            Text(activity.name).font(.largeTitle.weight(.semibold))
            Text(Format.longDate(activity.startDate, in: activity.timeZone))
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
                if isEditingNote {
                    Text("Échap pour terminer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let noteFailure {
                Text(noteFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if isEditingNote {
                noteEditor
            } else if note.isEmpty {
                Button {
                    beginEditingNote()
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
            } else {
                MarkdownText(
                    markdown: note, baseSize: Self.noteSize, hidesTagHashes: true
                )
                // No `textSelection` here, deliberately: a selectable `Text`
                // takes the click for itself, so only the empty surface beside
                // the words opened the editor — measured at the pointer, 13
                // August 2026. Selecting the note is what the editor is for,
                // and it is one click away. The journal's pane made the same
                // trade for the same reason.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture { beginEditingNote() }
            }
        }
        // Leaving the activity commits what was typed: the pane is rebuilt for
        // the next one, and a draft left behind would go nowhere.
        .onChange(of: activity.persistentModelID) { _, _ in
            if isEditingNote { endEditingNote() }
        }
        .onDisappear { if isEditingNote { endEditingNote() } }
    }

    private var noteEditor: some View {
        TextEditor(text: $noteDraft)
            .font(.system(size: Self.noteSize))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: 120)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
            .focused($noteFocused)
            .onChange(of: noteDraft) { _, _ in scheduleNoteSave() }
            .onKeyPress(.escape) {
                endEditingNote()
                return .handled
            }
    }

    private func beginEditingNote() {
        noteDraft = activity.activityDescription ?? ""
        noteFailure = nil
        isEditingNote = true
        noteFocused = true
    }

    private func endEditingNote() {
        noteSaveTask?.cancel()
        saveNote()
        isEditingNote = false
        noteFocused = false
    }

    /// A second after the typing stops, and again when the editor is left.
    ///
    /// Not on every keystroke: each one would be a write to the store, and the
    /// journal's day list, the tag counts and the search all read this text.
    /// Not on the way out alone either — a quit mid-sentence would take the
    /// sentence with it.
    private func scheduleNoteSave() {
        noteSaveTask?.cancel()
        noteSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNote()
        }
    }

    /// Through `ActivityDraft`, never straight into the model.
    ///
    /// The draft is what claims the field as edited, and a note written past
    /// it would be quietly overwritten by the next sync of that activity —
    /// which is the whole point of `editedFields`.
    private func saveNote() {
        var draft = ActivityDraft(activity)
        draft.notes = noteDraft
        guard draft.changedFields(comparedTo: activity).contains(.notes) else {
            return
        }
        draft.apply(to: activity)
        do {
            try modelContext.save()
            noteFailure = nil
        } catch {
            noteFailure = "La note n'a pas pu être enregistrée. "
                + error.localizedDescription
        }
    }

    private var statistics: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
            spacing: 16
        ) {
            ForEach(Self.statTiles(for: activity)) { tile in
                StatTile(tile.title, tile.value)
            }
        }
    }

    struct StatTileModel: Identifiable, Equatable {
        let title: String
        let value: String
        var id: String { title }
    }

    /// The statistics grid, as a list rather than a fixed layout.
    ///
    /// A tile with nothing to say is left out entirely instead of printing a
    /// dash: the grid was written for a ride, and on a swim or a gym session
    /// half of it said only that. Two figures are also dropped when they merely
    /// repeat the one beside them — Strava sends a run's estimated power as its
    /// own normalised power, and a watch that never paused makes elapsed time
    /// the moving time again.
    static func statTiles(for activity: Activity) -> [StatTileModel] {
        var tiles: [StatTileModel] = [
            StatTileModel(title: "Distance", value: Format.distance(activity.distance)),
            StatTileModel(
                title: "Temps en mouvement", value: Format.duration(activity.movingTime)
            ),
        ]
        func add(_ title: String, _ value: String) {
            tiles.append(StatTileModel(title: title, value: value))
        }

        if activity.elapsedTime != activity.movingTime {
            add("Temps total", Format.duration(activity.elapsedTime))
        }
        add("Dénivelé +", Format.elevation(activity.totalElevationGain))

        if activity.averageSpeed > 0 {
            add(
                "Vitesse moyenne",
                Format.speed(activity.averageSpeed, sport: activity.sportType)
            )
        }
        if activity.maxSpeed > 0 {
            add("Vitesse max", Format.speed(activity.maxSpeed, sport: activity.sportType))
        }
        if let average = activity.averageHeartrate, average > 0 {
            add("FC moyenne", Format.heartrate(average))
        }
        if let max = activity.maxHeartrate, max > 0 {
            add("FC max", Format.heartrate(max))
        }
        if let watts = activity.averageWatts, watts > 0 {
            add("Puissance moyenne", Format.power(watts))
        }
        if let normalised = activity.weightedAverageWatts, normalised > 0,
           normalised.rounded() != (activity.averageWatts ?? 0).rounded() {
            add("Puissance normalisée", Format.power(normalised))
        }
        if let cadence = activity.averageCadence, cadence > 0 {
            add("Cadence", Format.cadence(cadence, sport: activity.sportType))
        }
        if let calories = activity.calories, calories > 0 {
            add("Calories", Format.calories(calories))
        }
        if let gear = activity.gear {
            add("Matériel", gear.name)
        }
        return tiles
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
