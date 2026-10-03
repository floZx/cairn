import SwiftUI
import SwiftData

struct ActivityListView: View {
    let filter: ActivityFilter
    // `Activity.ID` (the macro-synthesized `PersistentModel` typealias) isn't
    // nameable via dot-syntax outside the file that declares `Activity`, even
    // within the same module — a known SwiftData/macro limitation. It aliases
    // to `PersistentIdentifier`, which is used directly here instead.
    /// A set, so several activities can be compared on one map. One selection
    /// still opens the usual detail pane.
    @Binding var selection: Set<PersistentIdentifier>

    /// Owned by the parent: the first row is picked once per launch, not again
    /// every time the list is rebuilt.
    @Binding var hasAutoSelected: Bool

    /// Commands this view cannot carry out itself — changing section, editing,
    /// deleting. Motions stay here, where the sorted rows are.
    let onCommand: (VimCommand) -> Void

    /// Every activity, newest first. The filter is applied below, in memory.
    ///
    /// It used to carry the filter's own predicate, which meant the parent had
    /// to re-identify this whole view on every change — `@Query` cannot be
    /// mutated in place — and a re-identified view is a destroyed one: the
    /// table was rebuilt on each keystroke and took the keyboard with it.
    /// Typing "27" in a distance field entered "2", lost the field, and
    /// dropped the "7" on the floor. Reported 13 August 2026.
    ///
    /// Filtering here instead costs one pass over the library per change:
    /// measured at 4.3 ms for 900 activities with a distance floor and a
    /// search term, which is a fraction of a frame and does not grow with
    /// typing speed. `apply(to:)` runs the same two stages the database and
    /// this view were already running as a pair.
    @Query(sort: [SortDescriptor(\Activity.startDate, order: .reverse)])
    private var query: [Activity]

    /// Les podiums des meilleurs efforts, pour la médaille de la colonne
    /// « Étiquettes ».
    @Environment(AppEnvironment.self) private var app

    // Le tri « Date » du menu, et non `startDate` : l'ordre est le même, mais
    // celui-là n'était reconnu par personne — ni le menu, qui n'y cochait
    // rien, ni les en-têtes de mois, qui ne s'affichaient pas.
    @State private var sortOrder = ActivitySort.date.comparators(ascending: false)

    /// Which presentation is showing. Persisted: it is a preference, not a mode
    /// — someone who prefers cards prefers them tomorrow too.
    @AppStorage(ActivityListStyle.storageKey)
    private var style: ActivityListStyle = .table

    /// Set by the probe below, used to follow the keyboard cursor.
    @State private var scroller = TableScroller()

    /// Where the keyboard cursor is, and what it last wrote to the selection.
    ///
    /// Deriving the starting point from `selection` on every motion looks right
    /// and is right at typing speed, but a held key fires sixty times a second
    /// and a `@Binding` write is not visible to the next read in the same
    /// runloop pass. Every repeat therefore started from the *same* row and
    /// landed on the same one — the key repeated and nothing moved.
    @State private var cursor: Int?
    @State private var cursorSelection: Set<PersistentIdentifier> = []

    /// Les lignes et la sélection du dernier rendu, pour le gestionnaire de
    /// touches.
    ///
    /// Ce gestionnaire est une fermeture que SwiftUI ne remplace pas toujours
    /// quand la vue est redessinée : il peut garder une copie de la vue
    /// antérieure à l'arrivée d'une sortie. Relevé le 3 octobre 2026 — la
    /// liste montrait 812 sorties, la nouvelle en tête, et `k` travaillait
    /// encore sur les 811 d'avant : il butait sur l'ancienne première et la
    /// nouvelle restait hors d'atteinte. Ce n'est pas systématique, d'où un
    /// défaut vu deux jours de suite puis introuvable à l'essai.
    ///
    /// Une classe tenue par `@State` est la même instance pour toutes les
    /// copies de la vue, vieilles comprises : le corps y dépose ce qu'il vient
    /// de calculer, et le gestionnaire lit là plutôt que dans ce qu'il a
    /// capturé. Pas observée, et c'est voulu : y écrire pendant le rendu ne
    /// doit pas en provoquer un autre.
    @State private var latest = LatestRows()

    /// Bumped whenever the keyboard should come back to the list.
    @State private var focusRequest = 0
    /// The selection `onAppear` made on its own, so the change it causes is
    /// not taken for a click — see the selection handler below.
    @State private var automaticSelection: Set<PersistentIdentifier>?

    /// Which columns are shown, in which order, at which width — right-click the
    /// header to choose, drag to reorder, exactly as in the Finder. Persisted in
    /// `AppStorage` rather than `SceneStorage` so it survives a relaunch and not
    /// merely a window restore.
    ///
    /// The key carries a version because a stored order overrides the declared
    /// one: moving a column in code would otherwise have no effect for anyone
    /// who had already used the table. Bump it when the default order changes.
    @AppStorage("activityColumns.v2")
    private var columnCustomization = TableColumnCustomization<Activity>()

    init(
        filter: ActivityFilter,
        selection: Binding<Set<PersistentIdentifier>>,
        hasAutoSelected: Binding<Bool>,
        onCommand: @escaping (VimCommand) -> Void
    ) {
        self.filter = filter
        self._selection = selection
        self._hasAutoSelected = hasAutoSelected
        self.onCommand = onCommand
    }

    private var rows: [Activity] {
        // Both stages, as the pair has to be run: the predicate narrows and
        // `matchesPrecisely` settles what SQL could not express. Running one
        // without the other silently over-reports — `apply(to:)` says so.
        filter.apply(to: query).sorted(using: sortOrder)
    }

    /// The row to select when the list first appears, or nil to leave the
    /// selection alone.
    ///
    /// Only ever the newest activity, and only when the user has chosen nothing:
    /// opening on an empty pane wastes the window, but overriding a selection the
    /// user made — or made a point of clearing — would be worse.
    static func initialSelection(
        rows: [Activity], current: Set<PersistentIdentifier>, hasAutoSelected: Bool
    ) -> PersistentIdentifier? {
        guard !hasAutoSelected, current.isEmpty else { return nil }
        return rows.first?.id
    }

    /// The row to select so the cards never stand alone, or nil.
    ///
    /// Cards are a list beside a pane: with nothing selected they stretched
    /// across the whole window, name at one end and date at the other. The
    /// table is different — full width is where its columns show — so it
    /// may still be left without a selection.
    ///
    /// A selection the search hides counts as none: the pane only shows the
    /// rows the list shows, so a stored id the filter keeps out closed it —
    /// typing a search in cards emptied the right-hand pane.
    static func keptSelection(
        style: ActivityListStyle, rows: [Activity], current: Set<PersistentIdentifier>
    ) -> PersistentIdentifier? {
        guard style == .cards, !rows.contains(where: { current.contains($0.id) }) else {
            return nil
        }
        return rows.first?.id
    }

    private func keepCardSelection() {
        if let first = Self.keptSelection(style: style, rows: rows, current: selection) {
            automaticSelection = [first]
            selection = [first]
        }
    }

    /// Runs a motion here, hands anything else to the parent.
    private func perform(_ command: VimCommand, in rows: [Activity]) {
        let delta: Int
        switch command {
        case let .move(value): delta = value
        case let .halfPage(down):
            delta = down ? VimMotion.halfPageRows : -VimMotion.halfPageRows
        case .first: delta = -rows.count
        case .last: delta = rows.count
        default:
            onCommand(command)
            return
        }

        guard let index = VimMotion.destination(
            from: startingPoint(in: rows), delta: delta, count: rows.count
        ) else { return }

        // Replaces rather than extends: these motions move the cursor, and a
        // growing selection would turn `j` into a way to select everything.
        cursor = index
        cursorSelection = [rows[index].id]
        selection = cursorSelection
        // And the list follows. Without this the cursor walks off the bottom of
        // the window and the list stops being navigable at the very moment it is
        // being navigated.
        scroller.scroll(toRow: tableRow(index, in: rows))
    }

    /// Where the next motion starts from.
    ///
    /// The remembered cursor when it is still true, the selection otherwise.
    /// Trusting the cursor is what makes a held key move more than one row; the
    /// two checks are what stop it lying after the list has changed underneath.
    private func startingPoint(in rows: [Activity]) -> Int? {
        if let cursor, cursor < rows.count, cursorSelection.contains(rows[cursor].id) {
            return cursor
        }
        // `latest` et non `selection` : la `Binding` lue depuis une copie
        // périmée de la vue rend la sélection d'avant — voir `latest`.
        let selection = latest.selection
        return selection.count == 1 ? rows.firstIndex { $0.id == selection.first } : nil
    }

    var body: some View {
        // Bound once: `rows` filters and sorts the whole query, and it used to be
        // recomputed for the table and again for each half of the title.
        let rows = rows
        latest.rows = rows
        latest.selection = selection
        return Group {
            if style == .cards {
                cards(rows)
            } else {
                table(rows)
            }
        }
        .navigationTitle(
            rows.count == 1 ? "1 activité" : "\(rows.count) activités"
        )
        // The window subtitle, so the count is never read as the whole library
        // when it is in fact a filtered slice of it.
        .navigationSubtitle(filter.summary ?? "")
        // Both presentations are backed by an `NSTableView`, and both would
        // otherwise pay for automatic row heights. See the probe's own note.
        // Keyed on the presentation: switching builds a different table, and a
        // probe that ran once would go on holding the destroyed one.
        //
        // Le tableau seul fait épingler ses lignes. Les fiches tiennent leur
        // hauteur de `defaultMinListRowHeight`, et depuis les en-têtes de mois
        // la ligne 0 qu'`apply` mesure est un en-tête : épinglées à sa
        // hauteur, les fiches se chevauchaient toutes.
        .background(TableBridge(pinsRowHeight: style == .table, scroller: scroller).id(style))
        // Clicking the selected row again clears it — the detail pane closes
        // and the list gets the width back, without reaching for ⌥⌘I.
        .background(DeselectOnRepeatClick {
            selection = []
            // The keyboard cursor went with it: leaving it behind meant the
            // next `j` resumed from a row nothing on screen pointed at.
            cursor = nil
            cursorSelection = []
        })
        // Motions are answered here, where the sorted rows are; everything
        // else goes to the parent, which is also what the statistics and the
        // map hand it.
        .vimKeys(focusRequest: focusRequest) { command in
            perform(command, in: latest.rows)
            return true
        }
        // Switching presentation destroys the table the keyboard was in, and
        // focus goes nowhere. Both halves are asked back: SwiftUI's focus, which
        // is what feeds `onKeyPress`, and AppKit's first responder, which is what
        // draws the selected row as active.
        .onChange(of: style) { _, _ in
            focusRequest += 1
            scroller.focusWhenAttached()
            keepCardSelection()
        }
        // A search or a sport picked in the sidebar can hide the open row.
        .onChange(of: filter) { _, _ in keepCardSelection() }
        // A selection that is not the one we wrote came from somewhere else — a
        // click in the list, a record in the statistics, a track on the map — so
        // the remembered cursor is stale and the next motion re-derives it.
        .onChange(of: selection) { _, new in
            if new != cursorSelection { cursor = nil }
            // A row picked by hand takes the keyboard with it. After a section
            // chosen with the mouse, the list deliberately claims nothing on
            // appearing (`vimKeysClaimentLeFocus`), and a click then made the
            // table AppKit's first responder without telling SwiftUI's focus,
            // which is what `onKeyPress` listens to: `j`, `k` and the arrows
            // went nowhere until the section was left and entered by keyboard.
            // Measured with a probe on 25 September 2026, after a round trip
            // through the food journal.
            //
            // Not for the selection `onAppear` makes by itself — claiming the
            // keyboard for that is the paling sidebar row this design avoids —
            // nor for the ones `j` and `k` write, which already have it.
            if new == automaticSelection {
                automaticSelection = nil
            } else if new != cursorSelection, !new.isEmpty {
                focusRequest += 1
                scroller.focusWhenAttached()
            }
            keepCardSelection()
        }
        // Une sortie ouverte d'ailleurs — le podium d'un record — alors que la
        // liste est déjà là : elle s'y place, comme au retour de la carte.
        .onChange(of: app.revealSelectionToken) { _, _ in
            if let selected = selection.first,
               let index = rows.firstIndex(where: { $0.id == selected }) {
                scroller.scrollWhenAttached(toRow: tableRow(index, in: rows))
            }
        }
        .onAppear {
            if let first = Self.initialSelection(
                rows: rows, current: selection, hasAutoSelected: hasAutoSelected
            ) {
                automaticSelection = [first]
                selection = [first]
            }
            // Set even when nothing was selected — an empty library on first
            // launch must not arm the auto-selection for the next filter change.
            hasAutoSelected = true
            // A selection made elsewhere — a track on the global map, a record
            // in the statistics — comes back selected but out of sight: the
            // list is built anew, scrolled to its top. Signalé.
            if let selected = selection.first,
               let index = rows.firstIndex(where: { $0.id == selected }) {
                scroller.scrollWhenAttached(toRow: tableRow(index, in: rows))
            }
        }
        .toolbar {
            // Only with the cards: the table sorts by clicking a header, and a
            // second control for the same thing would be one too many.
            if style == .cards {
                ToolbarItem { sortMenu }
            }
            ToolbarItem {
                Picker("Présentation", selection: $style) {
                    ForEach(ActivityListStyle.allCases) { option in
                        Label(option.displayName, systemImage: option.symbolName)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Basculer entre le tableau et les fiches")
            }
        }
    }

    /// Writes into the same `sortOrder` the table's headers drive, so switching
    /// presentation never reshuffles what is on screen.
    private var sortMenu: some View {
        Menu {
            ForEach(ActivitySort.allCases) { option in
                Button {
                    // Same field tapped twice reverses it, as a column header
                    // does — the one gesture everyone already knows.
                    sortOrder = option.comparators(
                        ascending: ActivitySort.current(sortOrder) == option
                            ? !ActivitySort.isAscending(sortOrder)
                            : option.startsAscending
                    )
                } label: {
                    if ActivitySort.current(sortOrder) == option {
                        Label(
                            option.displayName,
                            systemImage: ActivitySort.isAscending(sortOrder)
                                ? "chevron.up" : "chevron.down"
                        )
                    } else {
                        Text(option.displayName)
                    }
                }
            }
            // La présentation des fiches n'est plus ici : un bouton de tri
            // qui change aussi l'allure des fiches faisait deux choses, et le
            // menu Présentation la porte déjà.
        } label: {
            Label("Trier", systemImage: "arrow.up.arrow.down")
        }
        .help("Trier les fiches")
    }

    /// Des en-têtes de mois : les fiches, triées par date — voir `ActivityMonths`.
    private var showsMonths: Bool {
        style == .cards && ActivitySort.current(sortOrder) == .date
    }

    /// La ligne de la table qui porte la `index`-ième sortie, en-têtes de mois
    /// comptés quand il y en a.
    private func tableRow(_ index: Int, in rows: [Activity]) -> Int {
        showsMonths
            ? ActivityMonths.tableRow(forRow: index, in: rows, day: \.localDay)
            : index
    }

    /// The rich presentation: one card per activity.
    private func cards(_ rows: [Activity]) -> some View {
        List(selection: $selection) {
            if showsMonths {
                // Le mois une fois, dans un en-tête collant — celui du journal.
                ForEach(ActivityMonths.months(of: rows, day: \.localDay)) { month in
                    Section {
                        ForEach(month.rows) { card($0) }
                    } header: {
                        Text(month.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(rows) { card($0) }
            }
        }
        .listStyle(.inset)
        // Lets the column's material through — see `RootView.splitView`.
        .scrollContentBackground(.hidden)
        // The height SwiftUI assumes for rows it has not built yet. Its
        // default assumption is 24 pt under 50 pt cards, and a fast scroll
        // into unbuilt territory laid rows out at that estimate — cards drawn
        // over each other until a correction pass. With the estimate equal to
        // the real height there is nothing to correct, ever. (AppKit-level
        // row-height pinning cannot fix this list: SwiftUI's delegate serves
        // the heights — verified live, `usesAutomaticRowHeights` already
        // false, estimated rows answering 24.)
        .environment(\.defaultMinListRowHeight, ActivityCard.rowHeight)
    }

    private func card(_ activity: Activity) -> some View {
        ActivityCard(activity: activity)
            // With the pane closed the column takes the whole window,
            // and a card as wide put its date a screen away from its
            // name. Past this width the card stops growing.
            .frame(maxWidth: 720, alignment: .leading)
            .listRowInsets(ActivityCard.rowInsets)
            .tag(activity.id)
    }

    /// A figure in a table cell.
    ///
    /// Trailing and monospaced, which is the whole difference between a column
    /// of numbers and a list of them: left-aligned, "3,3 km" and "96,7 km"
    /// started at the same place and ended nowhere near each other, so nothing
    /// could be compared down the column without reading every row.
    private func figure(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func table(_ rows: [Activity]) -> some View {
        Table(
            rows,
            selection: $selection,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("Date", value: \.startLocalDate) { activity in
                Text(Format.numericDate(activity.startDate, in: activity.timeZone))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // Every date is now "09/08/2026" wide, so the column can be cut to
            // fit it exactly instead of to the longest month name.
            .width(min: 80, ideal: 88)
            .customizationID("date")

            // No `customizationID`, which is what makes this column permanent:
            // it carries the sport icon, so hiding it would leave rows
            // unreadable. It stays second unless the date is hidden.
            TableColumn("Nom", value: \.name) { activity in
                SportLabel(activity.name, sport: activity.sportType)
                    .fontWeight(.medium)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Distance", value: \.distance) { activity in
                figure(Format.distance(activity.distance))
            }
            .width(min: 80, ideal: 90)
            .customizationID("distance")

            TableColumn("Durée", value: \.movingTime) { activity in
                figure(Format.durationCompact(activity.movingTime))
            }
            .width(min: 80, ideal: 90)
            .customizationID("duration")

            TableColumn("D+", value: \.totalElevationGain) { activity in
                figure(Format.elevation(activity.totalElevationGain))
            }
            .width(min: 70, ideal: 80)
            .customizationID("elevation")

            TableColumn("D+/km", value: \.elevationPerKilometre) { activity in
                figure(Format.elevationPerKilometre(activity.elevationPerKilometre))
            }
            .width(min: 80, ideal: 90)
            .customizationID("elevationPerKilometre")

            TableColumn("Vitesse", value: \.averageSpeed) { activity in
                figure(Format.speed(activity.averageSpeed, sport: activity.sportType))
            }
            .width(min: 90, ideal: 100)
            .customizationID("speed")

            TableColumn("FC moy.", value: \.averageHeartrateOrZero) { activity in
                figure(Format.heartrate(activity.averageHeartrate))
            }
            .width(min: 80, ideal: 90)
            .customizationID("averageHeartRate")

            TableColumn("Étiquettes") { activity in
                HStack(spacing: 4) {
                    if let medals = app.bestEfforts.medals[activity.uuid] {
                        EffortMedalBadge(medals: medals, uuid: activity.uuid)
                    }
                    ForEach(activity.labels) { label in
                        Image(systemName: label.symbolName)
                            // The favourite keeps the yellow it has in the
                            // cards and in the detail pane; a star greyed out
                            // here read as a marker that was not set.
                            .foregroundStyle(
                                label == .favorite
                                    ? AnyShapeStyle(.yellow)
                                    : AnyShapeStyle(.secondary)
                            )
                    }
                }
                .help(activity.labels.map(\.displayName).joined(separator: ", "))
            }
            .width(min: 60, ideal: 80)
            .customizationID("labels")
        }
        // Lets the column's material through — see `RootView.splitView`.
        .scrollContentBackground(.hidden)
        // And so does this: hiding the scroll background is not enough on a
        // `Table`, which paints an opaque fill on every other row on top of
        // it. That striping is what made this presentation look solid where
        // the cards look like glass. The selection and the row separators
        // carry the eye across a row on their own.
        .alternatingRowBackgrounds(.disabled)
    }
}

/// Voir `ActivityListView.latest`.
@MainActor
private final class LatestRows {
    var rows: [Activity] = []
    var selection: Set<PersistentIdentifier> = []
}
