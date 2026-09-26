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

    /// The header's floor, so two activities open on the same block whether or
    /// not they carry markers.
    ///
    /// Its height used to be whatever its lines added up to: an outing with a
    /// workout type and a « Modifiée » line stood a good twenty points taller
    /// than one with neither, and moving between the two made the whole pane
    /// jump. The floor is the taller of the two, so the shorter one gains air
    /// rather than the taller one losing any.
    private static let headerMinHeight: CGFloat = 104

    let activity: Activity
    var onExpandMap: (() -> Void)?
    /// Opens the editor. The notes section calls it, which is what turns an
    /// empty journal entry into an invitation rather than a blank.
    var onEdit: (() -> Void)?
    /// Jumps to another activity — the « même parcours » rows use it, so a
    /// past effort on this course is one click away.
    var onSelectActivity: ((PersistentIdentifier) -> Void)?
    /// `J` et `K` tenus dans la liste : le volet défile, sans que la sélection
    /// bouge — `j` et `k` choisissent la sortie, `J` et `K` la lisent.
    var scrollRequest = PaneScrollRequest()
    /// Beside the global map: the pane keeps what describes the route —
    /// distance, time, climb, the altitude profile, the same-route list, the
    /// notes; neither the gear nor the weather — and
    /// leaves the rest to the activity itself, one button away. The map is
    /// gone too: the big one already shows the track, highlighted.
    var besideGlobalMap = false
    /// « Voir l'activité », beside the global map.
    var onOpenActivity: (() -> Void)?
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
    /// Vrai quand l'éditeur doit avoir le clavier.
    ///
    /// Un état ordinaire et non un `@FocusState` : c'est `NoteTextView` qui
    /// tient le premier répondant, et les deux mécaniques ne se parlent pas.
    @State private var noteFocused = false
    /// The pending write, so the note reaches the store a moment after the
    /// typing stops rather than at every letter.
    @State private var noteSaveTask: Task<Void, Never>?
    /// Said out loud under the editor: a note that failed to save while the
    /// screen goes on showing it is the silent loss this project exists to
    /// prevent.
    @State private var noteFailure: String?

    /// Distance under the cursor in a chart, mirrored on the map as a marker.
    @State private var hoverDistanceKm: Double?
    @State private var showsGarminSync = false
    @State private var showsAllLaps = false
    @AppStorage(MapStyle.storageKey) private var mapStyle: MapStyle = .standard
    @AppStorage(TrackColor.storageKey) private var trackColor: TrackColor = .accent

    /// Cached: the body re-evaluates on every mouse move while a chart is
    /// hovered, and deriving this from the blobs each time made hover pay an
    /// O(n) decode per event.
    private var trackModel: ActivityTrackModel {
        ActivityTrackModelCache.model(for: activity)
    }

    var body: some View {
        // The scrolling lives in its own view: its position changes on every
        // frame of a `J` held down, and here it rebuilt the whole pane each
        // time — 845 times in one probe — so a late frame now and then made
        // the pane jump. There, only the scroll view itself is redrawn.
        PaneScrollView(resetKey: activity.persistentModelID, request: scrollRequest) {
            VStack(alignment: .leading, spacing: 20) {
                // Lit by the sport's own colour, so opening an activity says
                // what kind it is before a word is read. A wider blur than the
                // charts get: this block is the tallest thing on the page, and
                // the same radius on it would read as a coloured panel.
                header
                    .frame(
                        maxWidth: .infinity, minHeight: Self.headerMinHeight,
                        alignment: .leading
                    )
                    .overlay(alignment: .trailing) { sportWatermark }
                    .ambientGlow(
                        activity.sportType.color, cornerRadius: 16, blurRadius: 80
                    )

                // No placeholder when there is no track: a pool swim or a gym
                // session simply has nowhere to be drawn, and a large empty
                // panel announcing that is worse than the map's absence.
                if !besideGlobalMap, trackModel.coordinates.count > 1 {
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

                // What the outing was done in and with, side by side, the
                // one under the other when the pane is narrow. The weather
                // sat in the header's corner first, where Strava has it, and
                // crowded the title as soon as the pane was dragged in.
                // Pas à côté de la carte globale : le matériel et la météo
                // disent la sortie, pas le parcours.
                if !besideGlobalMap {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ActivityGearRow(activity: activity)
                        ActivityWeatherView(activity: activity)
                    }
                }

                statistics

                if besideGlobalMap, let onOpenActivity {
                    Button(action: onOpenActivity) {
                        Label("Voir l'activité", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                    .help("Ouvrir la sortie dans Mes activités, avec ses courbes et ses tours")
                }

                SameRouteSection(activity: activity, onSelect: onSelectActivity)

                // Every chart runs along the distance: with none — a gym
                // session, a pool swim logged without lengths — the whole
                // curve collapses into a line at 0 km. Nothing then, not even
                // the note saying why, which would read as data missing.
                if activity.distance <= 0 {
                    EmptyView()
                } else if !chartSeries.isEmpty {
                    StreamChartsView(
                        series: chartSeries, hoverDistanceKm: $hoverDistanceKm
                    )
                } else if let message = Self.missingChartsMessage(
                    hasStreams: activity.streams != nil,
                    isSynced: activity.source.isSynced
                ) {
                    Label(message, systemImage: "chart.xyaxis.line")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // One lap is the whole activity again, figure for figure, a
                // few lines below the same figures.
                if !besideGlobalMap, activity.laps.count > 1 {
                    laps
                }
            }
            .padding()
        }
        .onChange(of: activity.persistentModelID) { _, _ in
            showsAllLaps = false
        }
        // The sport's light on the frosted pane behind the content: the window
        // material can only blend the desktop, so on a dark wallpaper it has
        // nothing to catch and the pane stays grey whatever the outing.
        .sportWash(activity.sportType.color, strength: SportWashStrength.detail)
        .navigationTitle(activity.name)
        .sheet(isPresented: $showsGarminSync) {
            GarminSyncSheet(activityUUID: activity.uuid, source: GarminSource(activity))
        }
        .task(id: garminCheckKey) {
            guard app.isGarminConnected else { return }
            // A beat first: `j` held down in the list opens a dozen activities
            // a second, and each would otherwise cost Garmin three requests.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await app.garminSync.checkIfNeeded(
                uuid: activity.uuid, source: GarminSource(activity)
            )
        }
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
            // The date first, above the name: when, then what — the order a
            // journal reads in.
            Text(Format.longDate(activity.startDate, in: activity.timeZone))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(activity.name).font(.largeTitle.weight(.semibold))
                // Only beside a title nobody wrote — « Course à pied le
                // matin », « Morning Ride » — where a better one is a click
                // away without opening the editor.
                if #available(macOS 26.0, *), TitleSuggestions.isBanal(activity.name) {
                    TitleSuggestionButton(
                        activity: activity, draft: ActivityDraft(activity), onPick: rename
                    )
                    .font(.title2)
                    // A fresh button for each activity: its titles are
                    // worked out once and kept, and they belong to this one.
                    .id(activity.uuid)
                }
            }

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
                // Right after Strava: the two services side by side, then what
                // happened here.
                garminStatus
                if let failure = app.edits.failures[activity.uuid] {
                    Button {
                        retryEdit()
                    } label: {
                        Label(failedEditLabel, systemImage: "exclamationmark.triangle")
                    }
                    .buttonStyle(.borderless)
                    .help(failure + "\nCliquer pour réessayer.")
                }
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

    /// Where the activity stands with Garmin, beside where it came from.
    ///
    /// In step: the same glyph as Strava's, so the line reads as two
    /// services agreeing; a click still checks again. Out of step: an
    /// invitation, found by the background check. Anything else — not
    /// signed in, still checking, no Garmin twin — says nothing.
    @ViewBuilder
    private var garminStatus: some View {
        if app.isGarminConnected {
            switch app.garminSync.state(uuid: activity.uuid, source: GarminSource(activity)) {
            case .synced:
                Button {
                    showsGarminSync = true
                } label: {
                    Label("Garmin", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .help("Garmin Connect dit la même chose que Cairn. Cliquer pour revérifier.")
            case .needsSync:
                Button {
                    showsGarminSync = true
                } label: {
                    Label("Synchroniser les infos sur Garmin Connect", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderless)
                .help("Titre, type, description ou matériel diffèrent sur Garmin Connect")
            case .unknown, .checking, .unavailable:
                EmptyView()
            }
        }
    }

    /// A title picked beside the heading: kept from the next sync and sent
    /// on to Strava and Garmin, as a title changed in the editor would be.
    private func rename(to title: String) {
        guard title != activity.name else { return }
        activity.name = title
        if activity.source.isSynced { activity.markEdited([.name]) }
        do {
            try modelContext.save()
        } catch {
            // Undone rather than left on screen: a heading showing a title
            // the store doesn't hold would be the silent loss this project
            // refuses. The old one comes back and nothing is sent.
            modelContext.rollback()
            return
        }
        let source = GarminSource(activity)
        let stravaID = activity.source.isSynced ? activity.stravaID : nil
        let uuid = activity.uuid
        let toStrava = app.isAuthenticated
        let toGarmin = app.isGarminConnected
        Task {
            await app.edits.propagate(
                [.name], uuid: uuid, stravaID: stravaID, source: source,
                toStrava: toStrava, toGarmin: toGarmin
            )
        }
    }

    private var failedEditLabel: String {
        let edits = app.edits.failedEdits[activity.uuid] ?? []
        if edits.count > 1 { return "Modifications non répercutées" }
        if case .gear = edits.first { return "Matériel non répercuté" }
        return "Titre non répercuté"
    }

    private func retryEdit() {
        let edits = app.edits.failedEdits[activity.uuid] ?? [.name]
        let source = GarminSource(activity)
        let stravaID = activity.source.isSynced ? activity.stravaID : nil
        let uuid = activity.uuid
        let toStrava = app.isAuthenticated
        let toGarmin = app.isGarminConnected
        Task {
            await app.edits.propagate(
                edits, uuid: uuid, stravaID: stravaID, source: source,
                toStrava: toStrava, toGarmin: toGarmin
            )
        }
    }

    /// Changes whenever the background check has something new to look at:
    /// another activity, an edit to this one, a sign-in.
    private var garminCheckKey: String {
        "\(activity.uuid)|\(GarminSource(activity).signature)|\(app.isGarminConnected)"
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
        // Sized from the header rather than fixed at 96: a header one line
        // shorter clipped the glyph flat across the top, which read as a
        // drawing error rather than as a watermark. Measured against the
        // block it sits in, it cannot be cut whatever the block holds.
        GeometryReader { proxy in
            Image(systemName: activity.sportType.symbolName)
                .font(.system(size: proxy.size.height * 0.86))
                .foregroundStyle(activity.sportType.color)
                .opacity(0.12)
                .frame(
                    width: proxy.size.width, height: proxy.size.height,
                    alignment: .trailing
                )
        }
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
                // La même surface que l'invitation à écrire, juste au-dessus.
                //
                // Elle ne l'avait pas, et le rapport était à l'envers : la
                // carte allait à la proposition d'écrire, la note écrite
                // restait nue entre la carte du parcours et la grille des
                // chiffres — deux blocs autrement plus présents qu'elle. Elle
                // est pourtant la seule prose de l'écran, et la seule chose
                // qu'on ait mise là soi-même.
                //
                // Une surface plutôt qu'un cadre ou une couleur : c'est déjà
                // le vocabulaire de cet écran, et le plus discret des trois.
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
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
        VStack(alignment: .leading, spacing: 4) {
            CompletingNoteEditor(
                texte: $noteDraft,
                taille: Self.noteSize,
                focus: $noteFocused,
                onEchappement: { endEditingNote() }
            )
                .padding(2)
                .frame(minHeight: 120)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                .onChange(of: noteDraft) { _, _ in scheduleNoteSave() }
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

    /// The curves shown: all of them, or only the altitude beside the global
    /// map — the one that describes the route rather than the effort.
    private var chartSeries: [StreamSeries] {
        besideGlobalMap ? trackModel.series.filter { $0.id == "altitude" } : trackModel.series
    }

    /// The figures of the route itself, beside the global map.
    static let routeTileTitles: Set<String> = ["Distance", "Temps en mouvement", "Dénivelé +"]

    private var statistics: some View {
        let tiles = Self.statTiles(for: activity)
            .filter { !besideGlobalMap || Self.routeTileTitles.contains($0.title) }
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), alignment: .leading),
                count: besideGlobalMap ? 3 : 4
            ),
            spacing: 16
        ) {
            ForEach(tiles) { tile in
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
        var tiles: [StatTileModel] = []
        func add(_ title: String, _ value: String) {
            tiles.append(StatTileModel(title: title, value: value))
        }
        // No « 0 m »: a gym session has no distance and a pool no climb, and
        // a tile saying so read as a figure missing rather than as none.
        if activity.distance > 0 { add("Distance", Format.distance(activity.distance)) }
        add("Temps en mouvement", Format.duration(activity.movingTime))

        if activity.elapsedTime != activity.movingTime {
            add("Temps total", Format.duration(activity.elapsedTime))
        }
        if activity.totalElevationGain >= 1 {
            add("Dénivelé +", Format.elevation(activity.totalElevationGain))
        }

        // Named after what is shown: a pace for the sports read in minutes per
        // kilometre (or per 100 m), a speed for the others.
        let speedWord = Format.readsAsPace(activity.sportType) ? "Allure" : "Vitesse"
        if activity.averageSpeed > 0 {
            add(
                "\(speedWord) moyenne",
                Format.speed(activity.averageSpeed, sport: activity.sportType)
            )
        }
        if activity.maxSpeed > 0 {
            add("\(speedWord) max", Format.speed(activity.maxSpeed, sport: activity.sportType))
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
        return tiles
    }

    /// Past this many, the laps table shows the first ones and a link.
    static let collapsedLapCount = 8

    private struct LapRow: Identifiable {
        let id: PersistentIdentifier
        let number: Int
        let lap: Lap
    }

    /// A pool's pause between lengths: time on the clock, no distance.
    static func isRest(_ lap: Lap) -> Bool {
        lap.distance < 1 && lap.movingTime > 0
    }

    /// Every lap at its full height, in the pane's own scroll — no scroll
    /// inside the scroll, which was the table's own at eight rows. Past
    /// eight, the rest waits behind a link. Numbered from 1, whatever the
    /// watch counted from; the climb column only when something climbed.
    private var laps: some View {
        let sorted = activity.laps.sorted { $0.lapIndex < $1.lapIndex }
        let rows = sorted.enumerated().map { index, lap in
            LapRow(id: lap.persistentModelID, number: index + 1, lap: lap)
        }
        let shown = showsAllLaps ? rows : Array(rows.prefix(Self.collapsedLapCount))
        let climbs = sorted.contains { $0.totalElevationGain >= 1 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Tours").font(.headline)
            Table(shown) {
                TableColumn("#") { Text("\($0.number)") }.width(30)
                TableColumn("Distance") { row in
                    if Self.isRest(row.lap) {
                        Text("Repos").foregroundStyle(.secondary)
                    } else {
                        Text(Format.distance(row.lap.distance))
                    }
                }
                TableColumn("Temps") { Text(Format.duration($0.lap.movingTime)) }
                if climbs {
                    TableColumn("D+") { Text(Format.elevation($0.lap.totalElevationGain)) }
                }
                TableColumn("Vitesse") { row in
                    Text(Self.isRest(row.lap)
                        ? "" : Format.speed(row.lap.averageSpeed, sport: activity.sportType))
                }
                TableColumn("FC") { Text(Format.heartrate($0.lap.averageHeartrate)) }
            }
            .scrollDisabled(true)
            // Rebuilt from scratch when the D+ column comes or goes: a table
            // reused from one activity to the next kept its old headers and
            // slid the pace in under « D+ ». Seen on screen, 26 September.
            .id("\(activity.persistentModelID.hashValue)-\(climbs)")
            // Rows of 24 pt under a 30 pt header, measured on screen: at 28
            // a row, eight laps left a blank strip under the table.
            .frame(height: CGFloat(shown.count) * 24 + 30)
            if rows.count > Self.collapsedLapCount {
                Button(showsAllLaps ? "Afficher moins" : "Afficher les \(rows.count) tours") {
                    withAnimation(.easeOut(duration: 0.2)) { showsAllLaps.toggle() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }
}

/// Le sens dans lequel le clavier fait défiler le volet : 1 vers le bas, -1
/// vers le haut, 0 à l'arrêt.
struct PaneScrollRequest: Equatable {
    var direction = 0
}

/// Le défilement du volet au clavier, image par image.
///
/// Continu et non par crans : une animation relancée à chaque répétition de la
/// touche partait de la position mesurée, encore en plein mouvement, et le
/// volet sautait par à-coups — « pas fluide », signalé. Ici la position suivie
/// est la nôtre, avancée à chaque image d'une vitesse qui monte en quelques
/// dixièmes de seconde, et le volet s'arrête net au relâchement — comme un
/// défilement au trackpad.
///
/// Une pression brève, qui n'aurait presque rien parcouru, finit en glissant
/// jusqu'à la longueur d'un tap : un tap doit faire avancer quelque chose.
@MainActor
final class PaneScroller {
    private var timer: Timer?
    private var direction = 0
    private var position: CGFloat = 0
    private var origin: CGFloat = 0
    private var maximum: CGFloat = 0
    private var startedAt = Date()
    private var lastTick = Date()
    private var apply: ((CGFloat) -> Void)?
    /// After a short press: the glide to the tap's end, run by this same
    /// timer. It used to be a SwiftUI animation, and a press made while one
    /// was still running fought it for the position — the pane jumped back
    /// 23 pt before going on, measured with a probe on 26 September.
    private var settle: (from: CGFloat, to: CGFloat, at: Date)?

    /// Points par seconde au départ, et au bout de la montée.
    private static let initialSpeed: CGFloat = 700
    private static let topSpeed: CGFloat = 1800
    private static let rampSeconds: CGFloat = 0.35
    /// Un tap parcourt au moins ça.
    private static let tapDistance: CGFloat = 120
    private static let settleSeconds: Double = 0.18
    /// No step longer than a frame's worth: the first tick could come 40 ms
    /// after the key, and the pane leapt 28 pt at once.
    private static let longestStep: CGFloat = 1.0 / 60

    /// Starts, or carries on from where a motion still running has got to:
    /// the pane's reported offset lags the timer by a frame or two, and
    /// restarting from it went backwards.
    func start(
        direction: Int, from offset: CGFloat, maximum: CGFloat,
        apply: @escaping @MainActor (CGFloat) -> Void
    ) {
        let running = timer != nil
        timer?.invalidate()
        timer = nil
        settle = nil
        self.apply = apply
        self.direction = direction
        self.maximum = maximum
        position = running ? clamp(position) : clamp(offset)
        origin = position
        startedAt = Date()
        lastTick = startedAt
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A long press stops where it is; a short one glides on to a tap's
    /// length, so a tap always moves something.
    func stop() {
        guard timer != nil, settle == nil else { return }
        if abs(position - origin) < Self.tapDistance {
            let target = clamp(origin + CGFloat(direction) * Self.tapDistance)
            settle = (position, target, Date())
        } else {
            cancel()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        settle = nil
    }

    private func tick() {
        let now = Date()
        if let settle {
            let t = min(1, now.timeIntervalSince(settle.at) / Self.settleSeconds)
            // Ease-out: fast at first, carrying the press's speed, then soft.
            let eased = 1 - pow(1 - t, 3)
            position = settle.from + (settle.to - settle.from) * CGFloat(eased)
            apply?(position)
            if t >= 1 { cancel() }
            return
        }
        let dt = min(CGFloat(now.timeIntervalSince(lastTick)), Self.longestStep)
        lastTick = now
        let elapsed = CGFloat(now.timeIntervalSince(startedAt))
        let ramp = min(1, elapsed / Self.rampSeconds)
        let speed = Self.initialSpeed + (Self.topSpeed - Self.initialSpeed) * ramp
        let next = clamp(position + CGFloat(direction) * speed * dt)
        guard next != position else { return }
        position = next
        apply?(next)
    }

    private func clamp(_ y: CGFloat) -> CGFloat {
        min(max(y, 0), maximum)
    }
}

/// The pane's scroll view, with the keyboard scrolling that drives it.
///
/// Apart from the pane on purpose: everything that changes while scrolling —
/// the position, the geometry, the key scroller — is state of this view, so a
/// frame of scrolling redraws this and not the content, which was built once
/// by the pane and is only handed over.
struct PaneScrollView<Content: View>: View {
    /// Another activity opens at the top of its pane, not where the last one
    /// was left.
    let resetKey: PersistentIdentifier
    let request: PaneScrollRequest
    @ViewBuilder let content: Content

    @State private var position = ScrollPosition()
    /// Written on every frame and read only when a key goes down: in a box,
    /// so writing it redraws nothing.
    @State private var geometry = GeometryBox()
    @State private var scroller = PaneScroller()

    @MainActor
    final class GeometryBox {
        var value = PaneScrollGeometry()
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollPosition($position)
        // In the coordinates `scrollTo(y:)` takes, which start below the
        // toolbar: the content offset starts above it, 51 pt higher. Handed
        // the raw offset, `J` began every press by jumping back those 51 pt
        // — the bounce each tap made, measured with a probe on 26 September.
        .onScrollGeometryChange(for: PaneScrollGeometry.self) { g in
            PaneScrollGeometry(
                offset: g.contentOffset.y + g.contentInsets.top,
                maximum: max(
                    0,
                    g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom
                        - g.containerSize.height
                )
            )
        } action: { _, new in
            geometry.value = new
        }
        .onChange(of: request.direction) { _, direction in
            if direction == 0 {
                scroller.stop()
            } else {
                scroller.start(
                    direction: direction,
                    from: geometry.value.offset,
                    maximum: geometry.value.maximum
                ) { y in position.scrollTo(y: y) }
            }
        }
        .onChange(of: resetKey) { _, _ in
            scroller.cancel()
            position.scrollTo(edge: .top)
        }
        .onDisappear { scroller.cancel() }
    }
}

/// Où en est le défilement du volet, et jusqu'où il peut aller.
struct PaneScrollGeometry: Equatable {
    var offset: CGFloat = 0
    var maximum: CGFloat = 0
}

