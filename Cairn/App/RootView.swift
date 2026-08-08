import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modelContext) private var modelContext
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var filter = ActivityFilter.none
    // See the comment on `ActivityListView.selection`: `Activity.ID` can't be
    // named from this file, so `PersistentIdentifier` is used directly.
    @State private var selectedActivities: Set<PersistentIdentifier> = []
    /// Whether the list has already picked its opening row. Held here rather than
    /// in the list, which `.id(filter)` re-instantiates on every filter change.
    @State private var hasAutoSelected = false
    /// Which map, if any, is filling the window.
    @State private var expandedMap: ExpandedMap?
    /// Which editor is open, if any. One state rather than two booleans: the two
    /// modes are exclusive and a pair of flags would let both be true.
    @State private var editor: ActivityEditorSheet.Mode?
    /// The activity a confirmation dialog is about to delete. Introduced here
    /// for the toolbar's Supprimer button; the confirmation itself is task 7's.
    @State private var pendingDeletion: Activity?
    /// Set when a write the user believes already happened — a delete, a
    /// restore, a save from the editor sheet — actually failed. Both `delete`
    /// and the editor's `onSave` change what is on screen (the selection
    /// clears, the sheet dismisses) before `try?` used to hide a failed
    /// `context.save()` behind a screen that already looks correct.
    @State private var writeFailureMessage: String?
    /// Whether the keyboard map is on screen, opened with `?`.
    @State private var showsKeyboardHelp = false
    /// Whether the editor about to open should start in the note field.
    ///
    /// Carried beside `editor` rather than inside its `Mode`: the mode says
    /// *what* is being edited and feeds `sheet(item:)`'s identity, while this
    /// says where to put the cursor — folding it in would give the same activity
    /// two identities and present the sheet twice.
    @State private var editorFocusesNotes = false
    /// Focus of the search field, so `/` can reach it.
    ///
    /// Held here rather than in the list: `.searchable` is applied to the list
    /// from this view, and `.searchFocused` only binds the field of the
    /// `searchable` in its own chain.
    @FocusState private var searchFieldFocused: Bool
    /// The list's presentation, held here too so the shortcut reaches it from
    /// anywhere. Same `AppStorage` key as the list's own, so the two never
    /// disagree — a second copy of the state would.
    @AppStorage(ActivityListStyle.storageKey)
    private var listStyle: ActivityListStyle = .table
    /// Kept apart from `writeFailureMessage`: a GPX that would not parse is not
    /// a failed save, and telling the user their work was lost when it was not
    /// is its own kind of wrong.
    @State private var fileMessage: String?
    /// Shared with every map so the chosen background and colour carry over.
    @AppStorage(MapStyle.storageKey) private var expandedStyle: MapStyle = .standard
    @AppStorage(TrackColor.storageKey) private var expandedTrackColor: TrackColor = .accent
    @Query private var allActivities: [Activity]

    /// The selected activities, restricted to those the list actually shows.
    ///
    /// Resolved against the filtered set rather than the whole library: a filter
    /// can hide a selected activity, and a detail pane for a row that is no
    /// longer in the list is a pane the list offers no way to close. The stored
    /// ids are deliberately left alone, so lifting the filter brings the
    /// selection back rather than silently discarding it.
    ///
    /// Narrowed to the selected ids *before* the filter runs, not after. The set
    /// it yields is the same either way, but this property is read four
    /// or five times per pass of `body` — for the detail pane, the comparison
    /// map, and every toolbar button's `disabled` — and the old order ran the
    /// filter over the whole library each time. Running it over the one or two
    /// activities actually selected turns each of those passes from 840
    /// predicate evaluations into one.
    private var selection: [Activity] {
        guard !selectedActivities.isEmpty else { return [] }
        return filter.apply(
            to: allActivities.filter { selectedActivities.contains($0.id) }
        )
    }

    /// The one selected activity, or nil as soon as there are several: the
    /// detail pane shows figures for one outing and a comparison map for more.
    private var selected: Activity? {
        selection.count == 1 ? selection.first : nil
    }

    /// The global map honours the same filters as the list — picking a sport in
    /// the sidebar or typing a search has to narrow the tracks too, otherwise
    /// the map contradicts every other view.
    private var mapActivities: [Activity] {
        filter.apply(to: allActivities)
    }

    /// Everything the filters keep except the date range, which the statistics
    /// view sets for itself — it has to reach into the preceding period to
    /// compare against it.
    private var statisticsActivities: [Activity] {
        filter.ignoringPeriod.apply(to: allActivities)
    }

    var body: some View {
        // The sheet, the deletion dialog, and the menu bridge below live on
        // this outer `Group` rather than on `splitView`: an empty library
        // shows `WelcomeView` instead, and a modifier attached only to the
        // branch that never renders yet never fires — `app.requestNewActivity`
        // stayed nil and ⌘N stayed disabled for exactly the person with no
        // Strava account, the one this journal is supposed to work for first.
        Group {
            if let expandedMap {
                fullWindowMap(expandedMap)
            } else if allActivities.isEmpty && !app.progress.isRunning {
                WelcomeView()
                    .frame(minWidth: 900, minHeight: 600)
            } else {
                splitView
            }
        }
        .sheet(item: $editor) { mode in
            ActivityEditorSheet(mode: mode, focusesNotes: editorFocusesNotes) { draft in
                // `Mode.apply` carries the switch that used to live here; kept
                // out of this closure so a test can reach it directly.
                let activity = mode.apply(draft)
                if case .create = mode {
                    modelContext.insert(activity)
                    selectedActivities = [activity.id]
                }
                do {
                    try modelContext.save()
                } catch {
                    // `apply` already mutated the object in memory: the screen
                    // shows the edit whether or not this succeeds, so silence
                    // here would be the worst kind — the user believes their
                    // work is saved.
                    writeFailureMessage =
                        "Votre modification n'a pas pu être enregistrée. \(error.localizedDescription)"
                }
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Supprimer « \($0.name) » ?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let pendingDeletion {
                    delete(pendingDeletion)
                }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            // `ActivitySource.deleteConfirmationMessage` carries the branch
            // that used to live here, tested on its own: see its doc comment
            // for why the two sources cannot share one text.
            Text(pendingDeletion?.source.deleteConfirmationMessage ?? "")
        }
        .alert(
            "Échec de l'enregistrement",
            isPresented: Binding(
                get: { writeFailureMessage != nil },
                set: { if !$0 { writeFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { writeFailureMessage = nil }
        } message: {
            Text(writeFailureMessage ?? "")
        }
        .alert(
            "Fichiers GPX",
            isPresented: Binding(
                get: { fileMessage != nil },
                set: { if !$0 { fileMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { fileMessage = nil }
        } message: {
            Text(fileMessage ?? "")
        }
        .sheet(isPresented: $showsKeyboardHelp) {
            KeyboardHelpSheet { showsKeyboardHelp = false }
        }
        .onAppear {
            app.requestNewActivity = { editor = .create }
            app.requestEditSelection = { if let selected { editor = .edit(selected) } }
            app.requestDeleteSelection = { pendingDeletion = selected }
            app.requestToggleFavorite = { toggleFavorite() }
            app.requestImportGPX = { chooseGPXFilesToImport() }
            app.requestExportGPX = { exportGPX(selection) }
            app.requestToggleListStyle = { listStyle = listStyle.toggled }
        }
    }

    /// A map on its own, with the sidebar and the detail pane out of the way.
    @ViewBuilder
    private func fullWindowMap(_ expanded: ExpandedMap) -> some View {
        let map = Group {
            switch expanded {
            case .global:
                GlobalMapView(
                    activities: mapActivities,
                    region: regionBinding,
                    // Clicking a track leaves the full-window map for the pane
                    // that can actually show the activity.
                    onSelect: { id in
                        selectedActivities = [id]
                        expandedMap = nil
                    }
                )
            case .comparison:
                // Guarded because a selection can shrink under an expanded map:
                // one activity is a detail pane's business, not this map's.
                if selection.count > 1 {
                    ComparisonMapView(activities: selection)
                }
            case let .activity(id):
                if let activity = allActivities.first(where: { $0.id == id }) {
                    ActivityMapView(
                        coordinates: activity.displayCoordinates,
                        style: expandedStyle,
                        trackColor: expandedTrackColor
                    )
                    .mapChrome(style: $expandedStyle)
                }
            }
        }

        map
            .frame(minWidth: 900, minHeight: 600)
            .overlay(alignment: .topLeading) {
                Button {
                    expandedMap = nil
                } label: {
                    Label(
                        "Réduire",
                        systemImage: "arrow.down.right.and.arrow.up.left"
                    )
                }
                .buttonStyle(.plain)
                .mapControl()
                // Attached to the button, not to the view: `onExitCommand` only
                // fires for the focused view, and the map takes focus.
                .keyboardShortcut(.escape, modifiers: [])
                .help("Revenir à la liste — ou appuyez sur Échap")
                .padding()
            }
    }

    private var regionBinding: Binding<BoundingBox?> {
        Binding(
            get: { filter.region },
            set: { newRegion in
                filter.region = newRegion
                if newRegion != nil {
                    sidebarSelection = .all
                    // A region chosen from the expanded map has to reveal the
                    // list it just filtered.
                    expandedMap = nil
                }
            }
        )
    }

    private var showsGlobalMap: Bool { sidebarSelection == .globalMap }

    private var showsStatistics: Bool { sidebarSelection == .statistics }

    private var showsNutrition: Bool { sidebarSelection == .nutrition }

    private var showsWeight: Bool { sidebarSelection == .weight }

    /// One three-column split view for the whole app life, never two.
    ///
    /// An earlier version swapped between a two- and a three-column
    /// `NavigationSplitView` so the map could span the detail pane. That reset
    /// every column width on each switch: macOS restores widths per split-view
    /// identity, and changing the column count is a different identity. The
    /// structure is now fixed, and the map claims the space by collapsing the
    /// detail column instead.
    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } content: {
            // A plain frame rather than `navigationSplitViewColumnWidth`: that
            // modifier's ideal width applies whenever the column is first
            // shown, and swapping list for map may well count as that — which
            // would silently reset the width the user dragged.
            Group {
                if showsGlobalMap {
                    GlobalMapView(
                        activities: mapActivities,
                        region: regionBinding,
                        onExpand: { expandedMap = .global },
                        onSelect: { selectedActivities = [$0] }
                    )
                    .vimKeys(performOutsideTheList)
                } else if showsStatistics {
                    // Labelled rather than trailing: a trailing closure inside a
                    // `ViewBuilder` is read as view content, and the compiler
                    // then tries to make a `TableColumn` out of it.
                    StatisticsView(
                        activities: statisticsActivities,
                        onSelect: { selectedActivities = [$0] }
                    )
                    .vimKeys(performOutsideTheList)
                } else if showsNutrition {
                    // The vim modifier lives inside the view here — it must go
                    // dead while the add/edit sheets are up, and only the view
                    // knows when that is.
                    NutritionDayView(onCommand: performInNutrition)
                } else if showsWeight {
                    // Same command filter as the food journal: the weight
                    // screen is journal territory too, an invisible activity
                    // selection must stay unreachable from it.
                    WeightView(onCommand: performInNutrition)
                } else {
                    ActivityListView(
                        filter: filter,
                        selection: $selectedActivities,
                        hasAutoSelected: $hasAutoSelected,
                        onCommand: perform
                    )
                    .id(filter)
                        .searchable(
                            text: $filter.searchText,
                            prompt: "Rechercher une activité"
                        )
                        .searchFocused($searchFieldFocused)
                }
            }
            .frame(minWidth: 480)
        } detail: {
            detailColumn
        }
        // Makes the list absorb a sidebar toggle instead of the detail pane.
        .background(SplitViewHoldingPriorities())
        .toolbar { syncToolbar }
    }

    /// Removes an activity from the journal: from the current selection so the
    /// detail pane never keeps a live reference to a deleted object, then from
    /// the store — leaving a tombstone behind when it came from Strava.
    private func delete(_ activity: Activity) {
        selectedActivities.remove(activity.id)
        // The full-window map can only reach a deleted activity by identity
        // (`.activity(id)`), and ⌘⌫ is reachable while it fills the window
        // now that the toolbar and its shortcut live on the outer `Group`.
        // Without this, deleting from there leaves `expandedMap` pointing at
        // an id nothing renders for — no crash, but an empty window with no
        // way out of the full-window view except the still-live "Réduire"
        // button or Échap.
        if case let .activity(id) = expandedMap, id == activity.id {
            expandedMap = nil
        }
        // The selection is cleared above, before the write is attempted: a
        // failure here would otherwise leave the activity in place but
        // deselected, with nothing on screen to say the deletion did not
        // actually happen.
        do {
            try ImportMapper(context: modelContext).discard(activity)
        } catch {
            writeFailureMessage =
                "Votre suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    private func openEditor(_ activity: Activity, focusingNotes: Bool) {
        // Set before the sheet is presented: the flag is read as the sheet is
        // built, and assigning it afterwards would arrive one presentation late.
        editorFocusesNotes = focusingNotes
        editor = .edit(activity)
    }

    /// The food journal's command set: navigation, escape, help, closing the
    /// pane — and nothing that touches an activity. A selection made in the
    /// list survives invisibly behind this screen, and without the filter a
    /// stray `n` or `x` edited or deleted an outing nothing was showing.
    private func performInNutrition(_ command: VimCommand) -> Bool {
        guard !command.actsOnActivities else { return false }
        return performOutsideTheList(command)
    }

    /// The same commands, from a view that has no rows to move through.
    ///
    /// Motions are refused rather than silently ignored: the press falls through
    /// to whatever else might want it, instead of being swallowed by a view that
    /// had nothing to do with it.
    private func performOutsideTheList(_ command: VimCommand) -> Bool {
        switch command {
        case .move, .first, .last, .halfPage:
            return false
        default:
            perform(command)
            return true
        }
    }

    /// The keyboard commands the list cannot carry out on its own.
    private func perform(_ command: VimCommand) {
        switch command {
        case let .section(item):
            sidebarSelection = item
        case .edit:
            if let selected { openEditor(selected, focusingNotes: false) }
        case .editNotes:
            if let selected { openEditor(selected, focusingNotes: true) }
        case .delete:
            pendingDeletion = selected
        case .toggleFavorite:
            toggleFavorite()
        case .expandMap:
            if let selected { expandedMap = .activity(selected.id) }
        case .closePane:
            selectedActivities = []
        case .toggleListStyle:
            listStyle = listStyle.toggled
        case .showHelp:
            showsKeyboardHelp = true
        case .clear:
            // Escape peels one layer at a time, as it does everywhere else on
            // the system: the search first, since that is what narrowed the
            // list, and only then the selection.
            if !filter.searchText.isEmpty {
                filter.searchText = ""
            } else {
                selectedActivities = []
            }
            // Focus comes back to the list either way, so the very next key is
            // a motion again rather than a character typed into the field.
            searchFieldFocused = false
        case .openSearch:
            searchFieldFocused = true
        case .move, .first, .last, .halfPage:
            // Motions are carried out by the list, which has the sorted rows.
            break
        }
    }

    /// Stars, or unstars, every selected activity.
    ///
    /// One shared new value rather than a per-activity flip: toggling a mixed
    /// selection item by item would leave it just as mixed, which is not what
    /// pressing a button once means.
    private func toggleFavorite() {
        let activities = selection
        guard !activities.isEmpty else { return }
        let starred = !activities.allSatisfy(\.isFavorite)
        for activity in activities { activity.isFavorite = starred }
        do {
            try modelContext.save()
        } catch {
            writeFailureMessage =
                "Le favori n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }

    private func chooseGPXFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [Self.gpxType]
        panel.prompt = "Importer"
        panel.message = "Choisissez un ou plusieurs fichiers GPX à ajouter au journal"
        guard panel.runModal() == .OK else { return }
        importGPX(from: panel.urls)
    }

    /// Imports every chosen file, keeping the ones that worked.
    ///
    /// One bad file among ten does not cancel the other nine: the failures are
    /// listed by name at the end instead. Selecting what came in is what makes
    /// an import visible — otherwise the rows land somewhere in 840 others.
    private func importGPX(from urls: [URL]) {
        let importer = GPXImporter(context: modelContext)
        var imported: [Activity] = []
        var failures: [String] = []

        for url in urls {
            do {
                let track = try GPXParser.parse(data: try Data(contentsOf: url))
                imported.append(
                    try importer.import(
                        track,
                        fallbackName: url.deletingPathExtension().lastPathComponent
                    )
                )
            } catch {
                failures.append("\(url.lastPathComponent) : \(error.localizedDescription)")
            }
        }

        if !imported.isEmpty {
            do {
                try modelContext.save()
                selectedActivities = Set(imported.map(\.id))
                hasAutoSelected = true
            } catch {
                failures.append(
                    "L'enregistrement a échoué : \(error.localizedDescription)"
                )
            }
        }
        fileMessage = Self.importReport(imported: imported.count, failures: failures)
    }

    /// What to tell the user afterwards, or nil when everything worked and the
    /// new rows on screen already say so.
    static func importReport(imported: Int, failures: [String]) -> String? {
        guard !failures.isEmpty else { return nil }
        let head = imported == 0
            ? "Aucun fichier n'a pu être importé."
            : "\(imported) activité\(imported > 1 ? "s importées" : " importée"), les autres non :"
        return ([head] + failures).joined(separator: "\n")
    }

    private func exportGPX(_ activities: [Activity]) {
        guard !activities.isEmpty else { return }
        if let single = activities.count == 1 ? activities.first : nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [Self.gpxType]
            panel.nameFieldStringValue = GPXWriter.fileName(for: single)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            write([single], into: url.deletingLastPathComponent(), names: [url.lastPathComponent])
            return
        }
        // Several at once go to a folder: a save panel per activity would mean
        // twenty dialogs for twenty rows.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Exporter"
        panel.message = "Choisissez le dossier où écrire les \(activities.count) fichiers GPX"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        write(activities, into: directory, names: activities.map(GPXWriter.fileName(for:)))
    }

    private func write(_ activities: [Activity], into directory: URL, names: [String]) {
        var failures: [String] = []
        for (activity, name) in zip(activities, names) {
            do {
                try GPXWriter.document(for: activity)
                    .write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
            } catch {
                failures.append("\(name) : \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            fileMessage = (["Certains fichiers n'ont pas pu être écrits :"] + failures)
                .joined(separator: "\n")
        }
    }

    /// `.gpx` is not a system-declared type, so it is built from the extension;
    /// `.xml` is the honest fallback, since a GPX is one.
    private static let gpxType = UTType(filenameExtension: "gpx") ?? .xml

    /// A floor for the detail pane whenever it actually has something to show.
    ///
    /// Not decoration: the collapse below sets the column's width to zero, and
    /// AppKit hands a reopening column back the width it had — near nothing. With
    /// no remembered width to fall back on, as after a fresh build, the pane
    /// reopened a few points wide, its labels wrapped one letter per line.
    private static let detailMinWidth: CGFloat = 360

    @ViewBuilder
    private var detailColumn: some View {
        // Neither the map nor the statistics collapse the pane outright any
        // more: clicking a track on one, or a record on the other, opens the
        // activity beside it, and both give the width back when nothing is
        // selected.
        if let selected {
            ActivityDetailView(
                activity: selected,
                onExpandMap: { expandedMap = .activity(selected.id) },
                // The notes section is the one that asks for this, so it lands
                // in the field it invited the user to fill.
                onEdit: { openEditor(selected, focusingNotes: true) }
            )
            .frame(minWidth: Self.detailMinWidth)
        } else if selection.count > 1 {
            ComparisonMapView(
                activities: selection,
                onExpand: { expandedMap = .comparison }
            )
            .frame(minWidth: Self.detailMinWidth)
        } else {
            collapsedDetailColumn
        }
    }

    /// Nothing worth a pane: beside a full-width view, or with nothing selected.
    ///
    /// Squeezing the column shut gives the width back to the list, and doing it
    /// this way keeps the split view's identity — and therefore the widths the
    /// user chose.
    private var collapsedDetailColumn: some View {
        Color.clear.navigationSplitViewColumnWidth(0)
    }

    private var sidebar: some View {
        SidebarView(selection: $sidebarSelection, filter: $filter)
            .frame(minWidth: 260)
    }

    @ToolbarContentBuilder
    private var syncToolbar: some ToolbarContent {
            ToolbarItem(placement: .status) {
                if app.progress.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(app.progress.toolbarText)
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            // Reserved on the text alone, so the pill keeps a
                            // steady width as the counter ticks over without
                            // pinning its contents against one edge.
                            .frame(width: 96, alignment: .leading)
                    }
                    .help(app.progress.statusText)
                }
            }
            ToolbarItem {
                Button {
                    app.syncNow()
                } label: {
                    Label("Synchroniser", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!app.isAuthenticated || app.progress.isRunning)
                // Already worded for every phase: the last run's date and time
                // when idle, "Jamais synchronisé" before the first one, and what
                // is happening while a sync is in flight.
                .help(app.progress.statusText)
            }
            // Kept in place and merely disabled rather than appearing with the
            // selection: a toolbar whose buttons come and go is unsettling, and
            // this way the affordance is visible before it is needed.
            ToolbarItem {
                Button {
                    selectedActivities = []
                } label: {
                    Label("Fermer le panneau", systemImage: "sidebar.trailing")
                }
                // A letter, not a digit: on an AZERTY keyboard the top row
                // needs shift for its numbers, so ⌥⌘0 is really ⇧⌥⌘0 and half
                // unreachable. ⌥⌘I is the Finder's inspector shortcut, and this
                // is the same pane on the same side.
                .keyboardShortcut("i", modifiers: [.option, .command])
                .disabled(selection.isEmpty)
                .help("Fermer le panneau de droite et désélectionner (⌥⌘I)")
            }
            // Grouped, not three loose buttons: the toolbar already carries three
            // items, and six side by side is where it stops reading as a toolbar.
            // These three act on the selected activity and belong together.
            ToolbarItemGroup {
                Button {
                    editor = .create
                } label: {
                    Label("Nouvelle activité", systemImage: "plus")
                }
                .help("Ajouter une activité saisie à la main")

                Button {
                    toggleFavorite()
                } label: {
                    // Filled when every selected activity is already a favourite,
                    // so the icon says what the button is about to do.
                    Label(
                        "Favori",
                        systemImage: selection.allSatisfy(\.isFavorite) && !selection.isEmpty
                            ? "star.fill" : "star"
                    )
                }
                .disabled(selection.isEmpty)
                .help("Marquer ou retirer des favoris")

                Button {
                    if let selected { editor = .edit(selected) }
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                .disabled(selected == nil)
                .help("Modifier l'activité sélectionnée")

                Button {
                    pendingDeletion = selected
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                .disabled(selected == nil)
                .help("Supprimer l'activité sélectionnée")
            }
    }
}

/// Which map is filling the window, if any.
private enum ExpandedMap: Equatable {
    case global
    case comparison
    case activity(PersistentIdentifier)
}
