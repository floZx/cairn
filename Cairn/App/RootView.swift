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
    @Environment(\.colorScheme) private var colorScheme
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
    /// Whether the food journal's side panel (calendar + day summary) is up.
    /// `AppStorage` rather than `State`: closing the panel is a workspace
    /// choice, and it should still be closed after a relaunch.
    @AppStorage("nutritionPanelVisible") private var nutritionPanelVisible = true
    /// The day the food journal and its side panel are showing — lifted here
    /// so the mini calendar (in the detail column) and the journal (in the
    /// content column) share one binding rather than drifting apart.
    @State private var nutritionDateKey = DateKey(Date())
    /// The journal's own selection, search and ticked tags. Held here rather
    /// than in the list for the same reason as the activity list's: the
    /// sidebar's tag section and the search field both live outside it.
    @State private var journalSelection: DateKey?
    @State private var journalQuery = ""
    @State private var journalTags: Set<JournalTag> = []
    /// Bumped to bring the keyboard back to the list, or to the editor.
    @State private var journalListFocus = 0
    @State private var journalEditorFocus = 0
    @State private var journalPendingDeletion: DateKey?
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
    /// Only the outings that wrote something down.
    ///
    /// Narrowed in the fetch rather than after it: the journal merges these
    /// into its days on every pass of `body`, and that is affordable for the
    /// few dozen outings carrying a note where it would not be for the whole
    /// library.
    @Query(filter: #Predicate<Activity> {
        $0.activityDescription != nil && $0.activityDescription != ""
    })
    private var notedActivities: [Activity]

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
        .confirmationDialog(
            journalPendingDeletion.map {
                "Supprimer la note du \(Format.fullDate($0.date())) ?"
            } ?? "",
            isPresented: Binding(
                get: { journalPendingDeletion != nil },
                set: { if !$0 { journalPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let date = journalPendingDeletion {
                    // Deleted first: `delete` clears any failed-write flag on
                    // that date, and only then will `selectJournalNote` agree
                    // to leave it.
                    app.journal.delete(date)
                    if journalSelection == date { selectJournalNote(nil) }
                }
                journalPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { journalPendingDeletion = nil }
        } message: {
            Text("Le fichier part à la corbeille : il reste récupérable.")
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
            // ⌘N means "make the thing this section is about": an activity in
            // the list, today's note in the journal. One shortcut rather than
            // two, since the two can never both apply.
            app.requestNewActivity = {
                if showsJournal {
                    openTodaysNote()
                } else {
                    editor = .create
                }
            }
            app.requestEditSelection = { if let selected { editor = .edit(selected) } }
            app.requestDeleteSelection = {
                if showsJournal {
                    journalPendingDeletion = journalSelectionHasFile
                        ? journalSelection : nil
                } else {
                    pendingDeletion = selected
                }
            }
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

    /// Whether the toolbar's activity buttons have anything to act on.
    ///
    /// Beside the food journal, the weight chart or the statistics they work
    /// on a selection those screens never show — a Supprimer that would take
    /// away an outing the user cannot see, a Favori whose star lights nothing.
    /// The sort, presentation and search controls need no such gate: they
    /// belong to the list's own toolbar and leave with it.
    ///
    /// The menu keeps every one of them, shortcuts included: this hides the
    /// buttons, it does not withdraw the commands.
    private var showsActivityActions: Bool {
        !showsJournal && !showsNutrition && !showsWeight && !showsStatistics
    }

    private var showsJournal: Bool { sidebarSelection == .journal }

    /// Every day the journal knows about: the vault's notes, and the days whose
    /// outings carry one.
    ///
    /// The activities are fetched already narrowed to the ones that wrote
    /// something (`notedActivities`), so this groups a few dozen rows rather
    /// than the whole library. The day an outing belongs to is `DateKey` of its
    /// instant in this Mac's calendar — the same rule `JournalDayActivities`
    /// filters the recap by, so a day's list and a day's recap can never
    /// disagree about which outings are its own.
    private var journalDays: [JournalDay] {
        var byDay: [DateKey: [String]] = [:]
        for activity in notedActivities.sorted(by: { $0.startDate < $1.startDate }) {
            guard let text = activity.activityDescription else { continue }
            byDay[DateKey(activity.startDate), default: []].append(text)
        }
        return JournalDay.merge(notes: app.journal.notes, activityNotes: byDay)
    }

    /// What the list shows: the search and the ticked tags together.
    private var filteredJournalDays: [JournalDay] {
        JournalDay.filter(journalDays, query: journalQuery, tags: journalTags)
    }

    /// Whether the selected day has a file of its own to delete. A day listed
    /// only because an outing wrote something has none.
    private var journalSelectionHasFile: Bool {
        guard let journalSelection,
              let day = journalDays.first(where: { $0.date == journalSelection })
        else { return false }
        return !day.note.isEmpty
    }

    /// The tag list the sidebar ticks, counted over both sources.
    private var journalTagCounts: [JournalTagTally.Row] {
        JournalTagTally.rows(for: journalDays.map(\.tags))
    }

    /// The list's selection, which stays put while a write is failing.
    ///
    /// `JournalStore.update(_:for:)` refuses to leave a note whose last write
    /// failed — it keeps the buffer, the edited date and its baseline where
    /// they are — and it refuses silently. A selection that moved anyway would
    /// leave the list showing one note while the store still edited another,
    /// and every word typed into the row on screen would go into the note
    /// behind it. So the selection follows the store's rule rather than
    /// discovering it too late.
    private var journalSelectionBinding: Binding<DateKey?> {
        Binding(
            get: { journalSelection },
            // Explicit closure, not a method reference: swift-frontend 6.3
            // aborts synthesising the thunk for `set: selectJournalNote`, with
            // no diagnostic — an IRGen crash, not a compile error.
            set: { selectJournalNote($0) }
        )
    }

    /// The sidebar calendar's day: the open note, or today when none is.
    ///
    /// Setting it goes the long way round on purpose. `selectJournalNote`
    /// flushes and may refuse — a note whose write failed is not one the list
    /// may leave — so the day is only opened in the store once the move has
    /// actually been agreed. Opening first would insert a row and hand the
    /// store a note the list never moved to.
    ///
    /// The editor is deliberately not focused. ⌘N means "write today", so it
    /// puts the caret in; clicking a day means "show me that day", and a note
    /// one wanted to read should not open with a cursor in it. The reader's
    /// own invitation is there for the day one meant to write.
    private var journalDayBinding: Binding<DateKey> {
        Binding(
            get: { journalSelection ?? DateKey(Date()) },
            set: { day in
                selectJournalNote(day)
                if journalSelection == day { app.journal.open(day) }
            }
        )
    }

    /// Leaves the journal for an activity, from the day's recap above a note.
    ///
    /// The section has to change with the selection: the journal's own pane is
    /// the note, so an activity selected while it is showing would light up
    /// nothing. Selecting *before* switching, so the list's opening selection
    /// finds the pane already claimed and leaves it alone.
    ///
    /// The buffer is flushed by `onChange(of: sidebarSelection)`, which fires
    /// on the switch below — an outing opened mid-sentence must not cost the
    /// sentence.
    private func openActivity(_ id: PersistentIdentifier) {
        selectedActivities = [id]
        sidebarSelection = .all
    }

    private func selectJournalNote(_ date: DateKey?) {
        // The flush first, then the guard. A debounce that has not fired yet
        // is unwritten work, and it is *this* write that fails when a vault
        // has gone: reading the flag before flushing asks about a failure that
        // has not happened, lets the selection move, and only then discovers
        // it — the store stays on the note it could not write while the list
        // shows another, and everything typed into the one on screen is
        // refused. Worse with nothing selected: the pane collapses, so the
        // message explaining the refusal has nowhere left to render.
        app.journal.saveNow()
        guard app.journal.pendingWriteFailure == nil else { return }
        journalSelection = date
    }

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
                } else if showsJournal {
                    Group {
                        if app.journal.folder == nil {
                            JournalEmptyView(onChooseFolder: chooseJournalFolder)
                        } else {
                            JournalListView(
                                days: filteredJournalDays,
                                query: journalQuery,
                                // A folder that was renamed, or sits on a
                                // volume nobody mounted: the setting is kept,
                                // so the section has to be the one place that
                                // says why it is empty. Without it the list
                                // offered « ⌘N ouvre la note du jour », which
                                // opens a note that cannot be written.
                                loadError: app.journal.loadError,
                                selection: journalSelectionBinding,
                                focusRequest: journalListFocus,
                                onCommand: performInJournal,
                                onSelectTag: { journalTags.insert($0) },
                                onOpenEditor: { journalEditorFocus += 1 },
                                onDelete: { journalPendingDeletion = $0 }
                            )
                            .searchable(
                                text: $journalQuery,
                                prompt: "Rechercher dans le journal"
                            )
                            // The same `FocusState` as the activity list's
                            // field: only one of the two is ever on screen, and
                            // a second one would be a second thing for `/` to
                            // aim at.
                            .searchFocused($searchFieldFocused)
                        }
                    }
                } else if showsNutrition {
                    // The vim modifier lives inside the view here — it must go
                    // dead while the add/edit sheets are up, and only the view
                    // knows when that is.
                    NutritionDayView(
                        dateKey: $nutritionDateKey,
                        onCommand: performOutsideActivities
                    )
                } else if showsWeight {
                    // Same command filter as the food journal: the weight
                    // screen is journal territory too, an invisible activity
                    // selection must stay unreachable from it.
                    WeightView(onCommand: performOutsideActivities)
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
            // The same frosted sheet as the detail pane, so the two content
            // columns read as one surface and only the sidebar stands apart.
            // At the column rather than on the list: SwiftUI paints the
            // column's own fill above anything a child puts behind itself.
            .background(
                VisualEffectBackground(material: .underWindowBackground)
                    .ignoresSafeArea(edges: .top)
            )
        } detail: {
            detailColumn
                // The pane has no fill of its own — with the window opened up
                // for the sidebar's material, the desktop came straight
                // through it and the figures sat on someone else's window.
                // A frosted sheet of its own gives it back a surface, and the
                // right kind of one.
                // Deliberately not lifted the way the sidebar is: tried, and
                // measured at 47 against the sidebar's 53 and the list's 48,
                // which puts all three planes within five values of each
                // other — the flatness the lift was introduced to cure. The
                // sidebar is chrome and earns the raised plane; this pane is a
                // document, map and charts and photographs, and belongs with
                // the content it describes.
                .background(
                    VisualEffectBackground(material: .underWindowBackground)
                        .ignoresSafeArea(edges: .top)
                )
        }
        // Makes the list absorb a sidebar toggle instead of the detail pane.
        // One sheet for the whole window, the toolbar strip included.
        //
        // The two content columns used to reach up behind the toolbar each on
        // their own, and the boundary between them came with them: a hard line
        // straight through the middle of the bar, warmed on one side by the
        // detail pane's wash. A single sheet has no boundary to show. Only the
        // sidebar keeps a fill of its own up there, which is the one seam
        // macOS draws in a toolbar anyway.
        // A guard, never meant to be seen: every column paints over it. It is
        // here so that no strip of an opened-up window is ever left bare.
        .background(
            VisualEffectBackground(material: .underWindowBackground)
                .ignoresSafeArea()
        )
        // The toolbar's own fill was a dark opaque band laid across three
        // frosted columns — 28 where the sidebar under it reads 58. Hidden, it
        // lets each column's material rise into it, so the bar carries the
        // tone of whatever it sits above.
        //
        // The cost, and it is a real one: that fill was also what covered the
        // split view's dividers, which now run the full height of the window,
        // toolbar included. Every replacement tried — a thin material, a
        // lighter sheet behind it — turns out to impose its own tone on the
        // whole width, which puts a band back over the sidebar. One uniform
        // strip cannot match two different columns; this way round at least
        // the tones are right.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(SplitViewHoldingPriorities(
            paneKind: showsJournal ? .journal
                : (showsNutrition ? .nutrition : .activity)
        ))
        // Arriving at the statistics gives the whole width to the charts: the
        // activity left selected in the list has nothing to do with the
        // figures now on screen, and its pane was simply in the way. Clicking
        // a record still opens that activity beside them — this fires on
        // entering the section, not on every selection made inside it.
        .onChange(of: sidebarSelection) { _, newValue in
            if newValue == .statistics { selectedActivities = [] }
        }
        // A pending debounce is unwritten work: leaving the note or the section
        // has to flush it, not race it.
        .onChange(of: journalSelection) { _, _ in
            app.journal.saveNow()
            // The banner belongs to the note it was raised over, and the flush
            // above has just settled it the way "Garder" would — the buffer
            // went to the file. Left standing it would sit over the next note
            // and say something untrue about it. Only on a change of note:
            // leaving the section keeps the same note selected, so coming back
            // to a banner still up is right.
            app.journal.dismissConflict()
        }
        .onChange(of: sidebarSelection) { _, _ in app.journal.saveNow() }
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

    /// The command set for the screens that show no activity — the journal, the
    /// food journal, the weight chart. An activity selection survives invisibly
    /// behind all three, and without this filter a stray `n` or `x` edited or
    /// deleted an outing nothing was showing.
    private func performOutsideActivities(_ command: VimCommand) -> Bool {
        guard !command.actsOnActivities else { return false }
        return performOutsideTheList(command)
    }

    /// The journal's own command set.
    ///
    /// It keeps the rule above — nothing may reach the activity selection
    /// surviving invisibly behind this screen — but three keys mean something
    /// here that they cannot mean beside a food log: `/` has a search field to
    /// aim at, Escape has a search and a selection of its own to peel, and `h`
    /// has a pane that does close.
    private func performInJournal(_ command: VimCommand) -> Bool {
        switch command {
        case .openSearch:
            searchFieldFocused = true
            return true
        case .clear:
            // One layer at a time, in the order the screen was narrowed.
            if !journalQuery.isEmpty {
                journalQuery = ""
            } else if !journalTags.isEmpty {
                journalTags = []
            } else {
                selectJournalNote(nil)
            }
            searchFieldFocused = false
            return true
        case .closePane:
            selectJournalNote(nil)
            return true
        default:
            return performOutsideActivities(command)
        }
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
        case .addFood, .newWeighIn, .moveEntryUp, .moveEntryDown, .dayForward,
             .loadRecipe, .saveRecipe:
            // Reaching here means no journal screen intercepted them: the
            // list, map or statistics are showing, where they mean nothing.
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

    private func chooseJournalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choisir"
        panel.message = "Choisissez le dossier qui contient vos notes du jour"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.journal.choose(url)
    }

    /// Opens today's note, creating it if it is not there. Nothing is written
    /// until something is typed — see `JournalStore.openToday`.
    private func openTodaysNote() {
        guard app.journal.folder != nil else {
            chooseJournalFolder()
            return
        }
        // Through `selectJournalNote`, never by assigning `journalSelection`:
        // the store refuses to leave a note whose write failed, and a direct
        // write here would move the list while the store stayed behind — the
        // desynchronisation task 6 built that guard to prevent.
        selectJournalNote(app.journal.openToday())
        // One tick later, for the same reason `VimKeys` waits before claiming
        // focus. With nothing selected the detail column is showing
        // `collapsedDetailColumn`, so the line above does not merely change
        // `JournalDetailView`'s `focusRequest` — it *inserts* that view, and
        // `onChange` never fires on insertion. Both writes land in one update
        // pass, so there is no intermediate render to catch the counter going
        // up. Deferring the bump gives the editor a view that already exists
        // to aim at. `onChange(initial:)` in the detail view would fix this
        // case and break every plain click-selection, which must not steal the
        // keyboard into the editor.
        Task { @MainActor in journalEditorFocus += 1 }
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

    /// The food journal's panel needs far less: a small calendar and a day's
    /// totals, where the activity pane carries a map and a photo strip. It
    /// used to inherit the activity floor and so could never be tucked away
    /// to the sliver it wants to be.
    private static let nutritionPanelMinWidth: CGFloat = 220

    @ViewBuilder
    private var detailColumn: some View {
        // Neither the map nor the statistics collapse the pane outright any
        // more: clicking a track on one, or a record on the other, opens the
        // activity beside it, and both give the width back when nothing is
        // selected.
        if showsJournal {
            if let date = journalSelection,
               let day = journalDays.first(where: { $0.date == date }) {
                JournalDetailView(
                    day: day,
                    text: app.journal.text(for: date),
                    textRevision: app.journal.textRevision,
                    // The store's three pieces of state go in, one notice comes
                    // out — the mapping is `JournalNotice`'s, and tested there.
                    notice: JournalNotice.notice(
                        conflict: app.journal.conflict,
                        writeFailure: app.journal.writeFailure,
                        failingDate: app.journal.pendingWriteFailure,
                        displayedDate: date
                    ),
                    focusRequest: journalEditorFocus,
                    // `open` rather than `beginEditing`: a day that is in the
                    // list only because an outing wrote something has no note
                    // in the store yet, and writing into it has to create one.
                    // Nothing reaches the disk until a character is typed.
                    onBeginEditing: { app.journal.open(date) },
                    onEdit: { app.journal.update($0, for: date) },
                    onSelectTag: { journalTags.insert($0) },
                    onSelectActivity: { openActivity($0) },
                    onReloadFromDisk: { app.journal.reloadConflicted() },
                    onDismissConflict: { app.journal.dismissConflict() },
                    onLeaveEditor: { journalListFocus += 1 }
                )
                .frame(minWidth: Self.detailMinWidth)
                // Another vault is another pane. The date is the only identity
                // a note has, so without this a folder change that happens to
                // hold the same day would leave the pane open — in the editor,
                // on a file it has never shown.
                .id(app.journal.folder)
            } else {
                collapsedDetailColumn
            }
        } else if showsNutrition {
            // The food journal claims the pane: the side panel replaces
            // whatever activity was left selected behind it — unless the user
            // closed it, which the toolbar button toggles. The weight screen
            // gets no pane at all: its charts already fill the window, and a
            // food calendar beside them answered a question nobody asked.
            if nutritionPanelVisible {
                NutritionSidePanel(selected: $nutritionDateKey)
                    .frame(minWidth: Self.nutritionPanelMinWidth)
            } else {
                collapsedDetailColumn
            }
        } else if showsWeight {
            collapsedDetailColumn
        } else if let selected {
            ActivityDetailView(
                activity: selected,
                onExpandMap: { expandedMap = .activity(selected.id) },
                // The notes section is the one that asks for this, so it lands
                // in the field it invited the user to fill.
                onEdit: { openEditor(selected, focusingNotes: true) },
                onSelectActivity: { selectedActivities = [$0] }
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
        SidebarView(
            selection: $sidebarSelection,
            filter: $filter,
            journalTags: $journalTags,
            journalDays: journalDays,
            journalTagCounts: journalTagCounts,
            journalDay: journalDayBinding,
            nutritionDay: $nutritionDateKey
        )
            .frame(minWidth: 260)
            .sportWash(washColor, strength: SportWashStrength.sidebar)
            // `ignoresSafeArea` so the material runs up behind the toolbar:
            // with the toolbar's own fill hidden below, a background stopping
            // at the safe area would leave the bare window there — which, on
            // a window opened up for the sidebar's blending, is the desktop.
            .background {
                ZStack {
                    // A lighter material than the content columns beside it,
                    // which is what makes the pane read as raised rather than
                    // as one more panel — with all three on the same material
                    // the sidebar had nothing to stand above.
                    VisualEffectBackground(material: .sidebar)
                    // A breath of light over the material, and the whole
                    // reason for it: `sidebar` and the content columns' own
                    // material land within a point or two of each other here,
                    // so the pane that should sit above the others read as
                    // level with them. Lifting this one rather than darkening
                    // its neighbours keeps the glass on all three.
                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.10)
                }
                // On the fill alone, never on the pane: applied to the whole
                // view it pulled the rows themselves up under the title bar,
                // where the traffic lights sat on top of the first one.
                //
                // Every edge, not just the top. The split view seats this pane
                // a few points inside its own column, and on a window opened
                // up for blending those points are not merely unpainted, they
                // are see-through — a bare strip of desktop down the left of
                // the window, and only there.
                .ignoresSafeArea()
            }
    }

    /// The colour the window borrows from what is open, if anything is.
    private var washColor: Color? {
        selected?.sportType.color
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
                    // In the food journal the pane is not driven by a
                    // selection, so the same button toggles the side panel
                    // instead of clearing a selection it doesn't have.
                    if showsNutrition {
                        nutritionPanelVisible.toggle()
                    } else if showsJournal {
                        // The journal's pane follows the note selection, and
                        // the activity selection it would otherwise clear is
                        // invisible here: without this branch the button — and
                        // the ⌥⌘I the key map calls good "depuis n'importe
                        // quelle vue" — left the note pane exactly where it was.
                        selectJournalNote(nil)
                    } else {
                        selectedActivities = []
                    }
                } label: {
                    Label("Fermer le panneau", systemImage: "sidebar.trailing")
                }
                // A letter, not a digit: on an AZERTY keyboard the top row
                // needs shift for its numbers, so ⌥⌘0 is really ⇧⌥⌘0 and half
                // unreachable. ⌥⌘I is the Finder's inspector shortcut, and this
                // is the same pane on the same side.
                .keyboardShortcut("i", modifiers: [.option, .command])
                // The weight screen has no pane to close; elsewhere the button
                // needs something to act on — a selected note in the journal,
                // a selected activity anywhere else.
                .disabled(
                    showsWeight
                        || (showsJournal && journalSelection == nil)
                        || (!showsNutrition && !showsJournal && selection.isEmpty)
                )
                .help(
                    showsNutrition
                        ? (nutritionPanelVisible
                            ? "Fermer le panneau de droite (⌥⌘I)"
                            : "Rouvrir le panneau de droite (⌥⌘I)")
                        : "Fermer le panneau de droite et désélectionner (⌥⌘I)"
                )
            }
            // Grouped, not three loose buttons: the toolbar already carries three
            // items, and six side by side is where it stops reading as a toolbar.
            // These three act on the selected activity and belong together —
            // and leave together, on the screens that show no activity.
            if showsActivityActions {
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

            if showsJournal {
                ToolbarItemGroup {
                    Button {
                        openTodaysNote()
                    } label: {
                        Label("Note du jour", systemImage: "square.and.pencil")
                    }
                    .help("Ouvrir la note d'aujourd'hui (⌘N)")

                    Button {
                        journalPendingDeletion = journalSelection
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    .disabled(!journalSelectionHasFile)
                    .help("Mettre la note sélectionnée à la corbeille")
                }
            }
    }
}

/// Which map is filling the window, if any.
private enum ExpandedMap: Equatable {
    case global
    case comparison
    case activity(PersistentIdentifier)
}
