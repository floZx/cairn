// Cairn/Features/Nutrition/NutritionDayView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// What a dragged food row carries: just enough to find the entry again.
/// `PersistentIdentifier` is Codable, so the payload stays tiny and honest.
struct FoodEntryDragPayload: Codable, Transferable {
    let id: PersistentIdentifier

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// The daily food journal — Cairn's take on suivinut's Day screen: navigation,
/// targets, totals, and full entry editing (add, edit, reorder, delete,
/// day-type choice).
struct NutritionDayView: View {
    /// The day shown — lifted to the caller so the detail column's mini
    /// calendar and this journal travel together.
    @Binding var dateKey: DateKey
    /// The vim commands this screen cannot handle itself, forwarded to the
    /// window (section jumps, escape, help). Taken as a closure so the vim
    /// modifier can live *here*: this view knows when its sheets are up, and
    /// keyboard handling must go dead exactly then — `onKeyPress` fires for
    /// focused descendants, and a sheet's text field is one.
    let onCommand: (VimCommand) -> Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealSlot.sortOrder) private var slots: [MealSlot]
    @Query private var days: [NutritionDay]
    @Query private var entries: [FoodEntry]
    @Query private var notes: [MealNote]
    @Query private var favoriteFoods: [FavoriteFood]
    @Query(sort: \WeightEntry.dateKeyRaw) private var weights: [WeightEntry]
    @AppStorage(NutritionSettings.proteinTargetKey)
    private var proteinTarget = NutritionSettings.defaultProteinTargetG
    @AppStorage(NutritionSettings.fatTargetKey)
    private var fatTarget = NutritionSettings.defaultFatTargetG
    @AppStorage(NutritionSettings.fiberTargetKey)
    private var fiberTarget = NutritionSettings.defaultFiberTargetG
    @AppStorage(NutritionSettings.weightGoalKey)
    private var weightGoal = NutritionSettings.defaultWeightGoalKg
    @State private var importMessage: String?
    @State private var addTargetSlot: MealSlot?
    @State private var isAddingWeight = false
    @State private var editingEntry: FoodEntry?
    @State private var writeFailureMessage: String?
    @State private var recipeTargetSlot: MealSlot?
    @State private var savingRecipeSlot: MealSlot?
    @State private var recipeName = ""
    @State private var showsRecipesManager = false
    @State private var noteTargetSlot: MealSlot?
    /// The entry a confirmation dialog is about to delete — same pattern as
    /// activities: an accidental `x` must cost one Escape, not a food.
    @State private var entryPendingDeletion: FoodEntry?
    @State private var cursor: DayCursor?
    /// An entry to put the cursor on once the query has caught up with it.
    @State private var pendingSelection: PersistentIdentifier?
    // Sorted the way suivinut lists day types: by target then name, so the
    // menu reads from rest day to biggest day.
    @Query(sort: [
        SortDescriptor(\DayType.kcalTarget), SortDescriptor(\DayType.name),
    ]) private var dayTypes: [DayType]

    /// Any presentation with text input or a default button: while one is up,
    /// keystrokes belong to it, never to the vim buffer underneath.
    private var isPresentingModal: Bool {
        addTargetSlot != nil || isAddingWeight || editingEntry != nil
            || importMessage != nil || writeFailureMessage != nil
            || recipeTargetSlot != nil || savingRecipeSlot != nil || showsRecipesManager
            || noteTargetSlot != nil || entryPendingDeletion != nil
    }

    /// The day the keyboard is on.
    ///
    /// A `@State` mirror of the binding rather than the binding itself, for the
    /// reason the journal's list already carries: a key handler is a closure
    /// built when the body was last evaluated, and `dateKey` read through it
    /// answers with the day that was on screen when the closure was made.
    ///
    /// Measured on 12 August 2026, instrumented rather than guessed at. The
    /// screen showed the 11th — seven, seven, nothing, twelve — while the row
    /// counts came back `[4, 0, 0, 0]`, the 12th's. The cursor therefore
    /// stopped at the last position the *12th* had, the dinner header, with a
    /// dozen lines visible underneath it and no way to reach them. `@State` is
    /// a reference into live storage: read here, it is always the day shown.
    ///
    /// Nil until the view first appears, which is why every read goes through
    /// `day` rather than touching this directly.
    @State private var keyboardDay: DateKey?

    /// The day every keyboard-side computation works from.
    private var day: DateKey { keyboardDay ?? dateKey }

    /// Rows per meal for the day under the cursor — its coordinate system.
    /// Recomputed on demand: cheap, and always consistent with what the
    /// screen shows.
    private var currentRowCounts: [Int] { rowCounts(for: day) }

    /// Taken as a parameter as well as read from `day`, because a handler that
    /// has just written the new day cannot read it back: a `@State` write is
    /// only visible to the next pass of the body.
    private func rowCounts(for day: DateKey) -> [Int] {
        let dayEntries = entries.filter { $0.dateKeyRaw == day.raw }
        return slots
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { slot in
                dayEntries.filter {
                    $0.mealSlot?.persistentModelID == slot.persistentModelID
                }.count
            }
    }

    /// The slot under the cursor, first slot when nothing is selected —
    /// `a`, `n`, `c`, `s` always have a target.
    private var cursorSlot: MealSlot? {
        let ordered = slots.sorted { $0.sortOrder < $1.sortOrder }
        guard let cursor, ordered.indices.contains(cursor.mealIndex) else {
            return ordered.first
        }
        return ordered[cursor.mealIndex]
    }

    /// The food entry under the cursor, nil on a header or empty screen.
    private var cursorEntry: FoodEntry? {
        guard let cursor, let rowIndex = cursor.rowIndex,
              let slot = cursorSlot else { return nil }
        let rows = entries
            .filter {
                $0.dateKeyRaw == day.raw
                    && $0.mealSlot?.persistentModelID == slot.persistentModelID
            }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard rows.indices.contains(rowIndex) else { return nil }
        return rows[rowIndex]
    }

    var body: some View {
        Group {
            if slots.isEmpty {
                onboarding
            } else {
                journal
            }
        }
        .vimKeys(enabled: !isPresentingModal) { command in
            switch command {
            // h/l travel through days, as in suivinut. `h` arrives as
            // `.closePane`, which is meaningless here: the journal's pane is
            // the side panel, and it is not closable.
            case .closePane:
                dateKey = day.advanced(by: -1)
                return true
            case .dayForward:
                dateKey = day.advanced(by: 1)
                return true
            case let .move(delta):
                cursor = DayCursorModel.move(
                    from: cursor, by: delta, rowCounts: currentRowCounts
                )
                return true
            case .first:
                cursor = DayCursorModel.positions(
                    rowCounts: currentRowCounts
                ).first
                return true
            case .last:
                cursor = DayCursorModel.positions(
                    rowCounts: currentRowCounts
                ).last
                return true
            case .addFood:
                if let slot = cursorSlot { addTargetSlot = slot }
                return true
            case .newWeighIn:
                isAddingWeight = true
                return true
            case .edit:
                if let entry = cursorEntry { editingEntry = entry }
                return true
            case .delete:
                if let entry = cursorEntry {
                    entryPendingDeletion = entry
                }
                return true
            case .toggleFavorite:
                if let entry = cursorEntry {
                    toggleFavorite(entry.persistentModelID)
                }
                return true
            case .moveEntryUp, .moveEntryDown:
                moveCursorEntry(up: command == .moveEntryUp)
                return true
            case .editNotes:
                if let slot = cursorSlot { noteTargetSlot = slot }
                return true
            case .loadRecipe:
                if let slot = cursorSlot { recipeTargetSlot = slot }
                return true
            case .saveRecipe:
                if let cursor, currentRowCounts.indices.contains(cursor.mealIndex),
                   currentRowCounts[cursor.mealIndex] > 0,
                   let slot = cursorSlot {
                    recipeName = ""
                    savingRecipeSlot = slot
                }
                return true
            case .toggleListStyle:
                cycleDayType()
                return true
            case .clear:
                if cursor != nil {
                    // Escape peels the cursor first, then the date, then the
                    // window — one layer per press, like everywhere else.
                    cursor = nil
                    return true
                }
                if day != DateKey(Date()) {
                    dateKey = DateKey(Date())
                    return true
                }
                return onCommand(command)
            default:
                return onCommand(command)
            }
        }
        // The arrows walk the rows, as j and k do. Both, and not one or the
        // other: the keys are there for hands that know vi, and nobody else
        // should have to learn it to move down a list.
        .onKeyPress(.upArrow) { moveCursor(by: -1) }
        .onKeyPress(.downArrow) { moveCursor(by: 1) }
        .onKeyPress(.leftArrow) {
            guard !isPresentingModal else { return .ignored }
            dateKey = day.advanced(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isPresentingModal else { return .ignored }
            dateKey = day.advanced(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !isPresentingModal, let entry = cursorEntry else {
                return .ignored
            }
            editingEntry = entry
            return .handled
        }
        // Seeded here and kept in step below: `day` answers for the binding
        // until the view has appeared, and for live storage afterwards.
        .onAppear { keyboardDay = dateKey }
        .onChange(of: dateKey) { _, arrived in
            keyboardDay = arrived
            // `arrived`, not `day`: the mirror above was just written, and a
            // `@State` write is only visible to the next pass of the body.
            cursor = DayCursorModel.clamp(
                cursor, rowCounts: rowCounts(for: arrived)
            )
        }
        .onChange(of: entries.count) { _, _ in
            cursor = DayCursorModel.clamp(cursor, rowCounts: currentRowCounts)
            if let pendingSelection, let position = position(of: pendingSelection) {
                cursor = position
                self.pendingSelection = nil
            }
        }
        .sheet(isPresented: $isAddingWeight) {
            WeightEntrySheet(
                existing: nil,
                defaultWeightKg: weights.last?.weightKg ?? weightGoal
            )
        }
        .alert(
            "Journal alimentaire",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// K/J: move the row, keep the cursor glued to it.
    private func moveCursorEntry(up: Bool) {
        guard let entry = cursorEntry, let position = cursor,
              let rowIndex = position.rowIndex else { return }
        let counts = currentRowCounts
        // The cursor can outlive a vanished meal (its first-slot fallback
        // does not guarantee `mealIndex` still exists) — a silent no-op
        // beats an out-of-range crash.
        guard counts.indices.contains(position.mealIndex) else { return }
        let target = rowIndex + (up ? -1 : 1)
        guard target >= 0, target < counts[position.mealIndex] else { return }
        do {
            try NutritionJournal.move(
                entry, direction: up ? -1 : 1, in: modelContext
            )
            cursor = DayCursor(mealIndex: position.mealIndex, rowIndex: target)
        } catch {
            writeFailureMessage =
                "Le déplacement n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }

    /// suivinut opened a picker on `t`; a cycle is just as fast for a handful
    /// of day types and needs no extra modal: … → last → none → first → …
    private func cycleDayType() {
        let current = days.first { $0.dateKeyRaw == dateKey.raw }?.dayType
        let next: DayType?
        if let current,
           let index = dayTypes.firstIndex(where: {
               $0.persistentModelID == current.persistentModelID
           }) {
            next = index + 1 < dayTypes.count ? dayTypes[index + 1] : nil
        } else {
            next = dayTypes.first
        }
        setDayType(next)
    }

    // MARK: - Journal

    private var journal: some View {
        // Filtered in memory, the way every other view applies
        // `ActivityFilter`: the journal holds hundreds of entries, not
        // enough to justify dynamic predicates.
        let dayEntries = entries.filter { $0.dateKeyRaw == dateKey.raw }
        let day = days.first { $0.dateKeyRaw == dateKey.raw }
        let dayNotes = notes.filter { $0.dateKeyRaw == dateKey.raw }
        let favorites = Set(favoriteFoods.map {
            FavoriteKey(foodName: $0.foodName, productCode: $0.productCode)
        })
        let model = NutritionDayModel.compute(
            entries: dayEntries, slots: slots, notes: dayNotes,
            dayType: day?.dayType,
            proteinTargetG: proteinTarget, fatTargetG: fatTarget,
            favoriteKeys: favorites
        )
        return ScrollView {
            // The cursor walks a plain stack here, not the rows of a table, so
            // nothing brings it back into sight on its own: `j` held down ran
            // the selection off the bottom of the window while the screen sat
            // still. The lists elsewhere reach into their `NSTableView` for
            // this; a stack has `scrollTo`, and every position carries its own
            // identity to be scrolled to.
            ScrollViewReader { scroller in
                VStack(alignment: .leading, spacing: 24) {
                    header(model)
                    summary(model)
                    Divider()
                    ForEach(
                        Array(model.meals.enumerated()), id: \.element.slotID
                    ) { mealIndex, meal in
                        mealSection(meal, mealIndex: mealIndex)
                    }
                }
                // No anchor: scrolls the least it can to uncover the row,
                // rather than yanking it to the middle of the window at every
                // step of a walk that was already visible.
                .onChange(of: cursor) { _, moved in
                    guard let moved else { return }
                    scroller.scrollTo(moved)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $addTargetSlot) { slot in
            AddFoodSheet(slot: slot, dateKey: dateKey, after: anchor(in: slot)) { added in
                // Resolved on the next pass rather than here: the query behind
                // `entries` has not seen the insertion yet, so the row index
                // asked for now would be the one from before it.
                pendingSelection = added.persistentModelID
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(entry: entry)
        }
        .sheet(item: $recipeTargetSlot) { slot in
            RecipePickerSheet(slot: slot, dateKey: dateKey)
        }
        .sheet(isPresented: $showsRecipesManager) {
            RecipesManagerSheet()
        }
        .sheet(item: $noteTargetSlot) { slot in
            MealNoteSheet(
                slot: slot, dateKey: dateKey,
                existingNote: notes.first {
                    $0.dateKeyRaw == dateKey.raw
                        && $0.mealSlot?.persistentModelID == slot.persistentModelID
                }?.note
            )
        }
        .alert(
            "Écriture impossible",
            isPresented: Binding(
                get: { writeFailureMessage != nil },
                set: { if !$0 { writeFailureMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(writeFailureMessage ?? "")
        }
        .confirmationDialog(
            entryPendingDeletion.map { "Supprimer « \($0.foodName) » ?" } ?? "",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            // Return confirms, Escape cancels: `x ⏎` stays a two-key delete,
            // but a stray `x` alone no longer costs a food. No `.destructive`
            // role: AppKit refuses to make a destructive button the default,
            // so with it the shortcut was silently dropped and ⏎ did nothing.
            // The title already asks the question; blue is a fair colour for
            // the answer.
            Button("Supprimer") {
                if let entry = entryPendingDeletion {
                    deleteEntry(entry.persistentModelID)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Annuler", role: .cancel) {}
        }
        .alert(
            "Enregistrer comme recette",
            isPresented: Binding(
                get: { savingRecipeSlot != nil },
                set: { if !$0 { savingRecipeSlot = nil } }
            )
        ) {
            TextField("Nom de la recette", text: $recipeName)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") { saveRecipe() }
        } message: {
            Text("Le repas actuel devient une recette réutilisable.")
        }
    }

    private func header(_ model: NutritionDayModel) -> some View {
        HStack(spacing: 12) {
            Button {
                dateKey = dateKey.advanced(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Jour précédent")
            Text(dayTitle)
                .font(.title2.weight(.semibold))
            Button {
                dateKey = dateKey.advanced(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Jour suivant")
            if dateKey != DateKey(Date()) {
                Button("Aujourd'hui") { dateKey = DateKey(Date()) }
            }
            Spacer()
            Menu {
                ForEach(dayTypes) { dayType in
                    Button("\(dayType.name) — \(dayType.kcalTarget) kcal") {
                        setDayType(dayType)
                    }
                }
                Divider()
                Button("Aucun") { setDayType(nil) }
            } label: {
                if let dayTypeName = model.dayTypeName {
                    Text(dayTypeName)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                } else {
                    Text("Choisir un jour-type")
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .buttonStyle(.borderless)
    }

    /// "Vendredi 8 août 2026" : only the first letter is raised —
    /// `.capitalized` would write every word capital, which French dates
    /// never do.
    private var dayTitle: String {
        let raw = Format.fullDate(dateKey.date())
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private func summary(_ model: NutritionDayModel) -> some View {
        HStack(alignment: .top, spacing: 24) {
            MacroGauge(
                title: "Calories", consumed: model.consumed.kcal,
                target: model.daily?.kcal, unit: "kcal"
            )
            MacroGauge(
                title: "Protéines", consumed: model.consumed.protein,
                target: model.daily?.protein, unit: "g"
            )
            MacroGauge(
                title: "Glucides", consumed: model.consumed.carbs,
                target: model.daily?.carbs, unit: "g"
            )
            MacroGauge(
                title: "Lipides", consumed: model.consumed.fat,
                target: model.daily?.fat, unit: "g"
            )
            // La cinquième, et la seule qui ne dépende pas du type de
            // journée : les calories suivent l'entraînement, les fibres non.
            FiberGauge(tally: model.fiber, target: fiberTarget)
        }
    }

    /// Fixed numeric columns so every meal's figures line up down the page —
    /// independent Grid widths made each meal drift, and suivinut's single
    /// shared table is what the eye expects. The name column absorbs the rest.
    private enum NumericColumn {
        // Widened with the type: a "0/1 237" total at the larger size no
        // longer fits the width its `.callout` version did.
        static let grams: CGFloat = 48
        static let kcal: CGFloat = 82
        static let macro: CGFloat = 66
        /// Plus étroite que les autres : les fibres tiennent en deux chiffres
        /// là où les glucides en demandent trois.
        static let fiber: CGFloat = 44
        static let spacing: CGFloat = 16
    }

    /// One "consumed/target" pair — suivinut's per-macro meal accounting,
    /// with its graduated overshoot: green once the meal has landed on its
    /// plan, orange while it is still close above it, red once frankly blown.
    private func pairText(_ consumed: Double, target: Double?) -> Text {
        let consumedText = "\(Int(consumed.rounded()))"
        guard let target else {
            return Text(consumedText).foregroundStyle(Color.secondary)
        }
        return Text("\(consumedText)/\(Int(target.rounded()))")
            .foregroundStyle(pairColor(consumed: consumed, target: target)
                             ?? Color.secondary)
    }

    /// Nil means "nothing to say yet" — the grey of a meal still being built.
    ///
    /// The overshoot is asked first: a figure past its target is past it,
    /// whatever else it is, and the warning outranks the encouragement.
    private func pairColor(consumed: Double, target: Double) -> Color? {
        switch NutritionMath.overshoot(consumed: consumed, target: target) {
        case .moderate: .orange
        case .heavy: .red
        case nil:
            NutritionMath.isOnTarget(consumed: consumed, target: target)
                ? .green : nil
        }
    }

    /// The meal's totals, sitting exactly under the grid's kcal/P/G/L
    /// columns: same fixed widths, same spacing, both blocks flush right.
    private func mealTotals(_ meal: NutritionDayModel.Meal) -> some View {
        HStack(spacing: NumericColumn.spacing) {
            pairText(meal.consumed.kcal, target: meal.target?.kcal)
                .frame(width: NumericColumn.kcal, alignment: .trailing)
            pairText(meal.consumed.protein, target: meal.target?.protein)
                .frame(width: NumericColumn.macro, alignment: .trailing)
            pairText(meal.consumed.carbs, target: meal.target?.carbs)
                .frame(width: NumericColumn.macro, alignment: .trailing)
            pairText(meal.consumed.fat, target: meal.target?.fat)
                .frame(width: NumericColumn.macro, alignment: .trailing)
            // Sans cible : les fibres se visent sur la journée, pas sur un
            // repas. Un chiffre seul, donc, là où les autres sont des paires.
            Text(meal.fiber.grams == 0 && meal.fiber.unknownCount > 0
                 ? "—" : "\(Int(meal.fiber.grams))")
                .frame(width: NumericColumn.fiber, alignment: .trailing)
                .foregroundStyle(meal.fiber.unknownCount > 0
                                 ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(.primary))
        }
        .font(.body.monospacedDigit())
        .help(Self.targetExplanation(meal))
    }

    /// What the second figure of each pair means, said on hover.
    ///
    /// Three meal targets do not add up to the day's, and cannot: a finished
    /// meal keeps its share of the plan so it can be compared to it, while the
    /// meal in progress carries what is actually left. Adding the three was
    /// the natural thing to try, and it produced a number that matched nothing
    /// — asked as "where is the error?" on 13 August 2026. There was none, and
    /// nothing on screen said so.
    static func targetExplanation(_ meal: NutritionDayModel.Meal) -> String {
        guard meal.target != nil else {
            return "Ce repas n'a pas de part du jour : ce qu'il apporte pèse "
                + "sur le budget des autres."
        }
        switch meal.targetKind {
        case .planShare:
            return "Repas terminé : sa cible est sa part du plan, "
                + "\(meal.pct) % de la journée, pour être comparée à ce qui a "
                + "été mangé."
        case .remaining:
            return "Repas en cours ou à venir : sa cible est ce qu'il reste de "
                + "la journée, réparti selon sa part. Manger exactement ça fait "
                + "atterrir le jour sur son objectif — c'est pourquoi les cibles "
                + "des repas ne s'additionnent pas à celle du jour."
        }
    }

    private func mealSection(
        _ meal: NutritionDayModel.Meal, mealIndex: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meal.slotName).font(.title3.weight(.semibold))
                Button {
                    addTargetSlot = slotModel(for: meal.slotID)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Ajouter un aliment à \(meal.slotName)")
                Menu {
                    Button("Charger une recette…") {
                        recipeTargetSlot = slotModel(for: meal.slotID)
                    }
                    Button("Enregistrer ce repas comme recette…") {
                        recipeName = ""
                        savingRecipeSlot = slotModel(for: meal.slotID)
                    }
                    .disabled(meal.rows.isEmpty)
                    Button("Note du repas…") {
                        noteTargetSlot = slotModel(for: meal.slotID)
                    }
                    Divider()
                    Button("Gérer les recettes…") { showsRecipesManager = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                mealTotals(meal)
            }
            .background(
                cursor == DayCursor(mealIndex: mealIndex, rowIndex: nil)
                    ? Self.cursorFill : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 4)
            )
            // The cursor is a selection and looks like one, so it has to be
            // clickable like one: it could only be moved with j and k, which
            // is a rule nothing on screen states.
            .contentShape(.rect)
            .onTapGesture {
                cursor = DayCursor(mealIndex: mealIndex, rowIndex: nil)
            }
            .id(DayCursor(mealIndex: mealIndex, rowIndex: nil))
            if meal.rows.isEmpty {
                Text("Rien de consigné")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                        Text("Aliment")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("g")
                            .frame(width: NumericColumn.grams, alignment: .trailing)
                        Text("kcal")
                            .frame(width: NumericColumn.kcal, alignment: .trailing)
                        Text("P")
                            .frame(width: NumericColumn.macro, alignment: .trailing)
                        Text("G")
                            .frame(width: NumericColumn.macro, alignment: .trailing)
                        Text("L")
                            .frame(width: NumericColumn.macro, alignment: .trailing)
                        Text("F")
                            .frame(width: NumericColumn.fiber, alignment: .trailing)
                            .help("Fibres, en grammes. Un tiret quand "
                                  + "l'aliment ne les annonce pas.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    ForEach(
                        Array(meal.rows.enumerated()), id: \.element.entryID
                    ) { rowIndex, row in
                        GridRow {
                            Button {
                                toggleFavorite(row.entryID)
                            } label: {
                                Image(systemName: row.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(
                                        row.isFavorite ? .yellow : .secondary
                                    )
                            }
                            .buttonStyle(.borderless)
                            .help(
                                row.isFavorite
                                    ? "Retirer des favoris" : "Ajouter aux favoris"
                            )
                            Text(row.name).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(Int(row.grams.rounded()))")
                                .frame(width: NumericColumn.grams, alignment: .trailing)
                            Text("\(Int(row.macros.kcal.rounded()))")
                                .frame(width: NumericColumn.kcal, alignment: .trailing)
                            Text("\(Int(row.macros.protein.rounded()))")
                                .frame(width: NumericColumn.macro, alignment: .trailing)
                            Text("\(Int(row.macros.carbs.rounded()))")
                                .frame(width: NumericColumn.macro, alignment: .trailing)
                            Text("\(Int(row.macros.fat.rounded()))")
                                .frame(width: NumericColumn.macro, alignment: .trailing)
                            // Un tiret, et non zéro : l'aliment n'a rien
                            // annoncé, ce qui n'est pas la même chose que
                            // n'en pas contenir. Toute la jauge du haut
                            // repose sur cette distinction.
                            Text(row.fiber.unknownCount > 0
                                 ? "—" : "\(Int(row.fiber.grams))")
                                .frame(width: NumericColumn.fiber, alignment: .trailing)
                                .foregroundStyle(row.fiber.unknownCount > 0
                                                 ? AnyShapeStyle(.tertiary)
                                                 : AnyShapeStyle(.primary))
                        }
                        // `monospacedDigit()` is a `Text` method; on a row
                        // the font modifier carries the same trait.
                        .font(.title3.monospacedDigit())
                        .background(
                            cursor == DayCursor(
                                mealIndex: mealIndex, rowIndex: rowIndex
                            )
                                ? Self.cursorFill
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        // Placed like the `.background` just above it: a
                        // modifier on a `GridRow` applies to each of its
                        // cells, so what can be clicked is exactly what the
                        // highlight covers, no more.
                        .contentShape(.rect)
                        .onTapGesture {
                            cursor = DayCursor(
                                mealIndex: mealIndex, rowIndex: rowIndex
                            )
                        }
                        // Like the `.background` above it, this lands on each
                        // cell of the row: they share one identity and one
                        // line, so scrolling to any of them is scrolling to
                        // the row.
                        .id(DayCursor(mealIndex: mealIndex, rowIndex: rowIndex))
                        .contextMenu {
                            Button("Éditer…") {
                                editingEntry = entry(for: row.entryID)
                            }
                            Button("Monter") { move(row.entryID, direction: -1) }
                            Button("Descendre") { move(row.entryID, direction: 1) }
                            Button("Basculer favori") { toggleFavorite(row.entryID) }
                            Divider()
                            Button("Supprimer", role: .destructive) {
                                entryPendingDeletion = entry(for: row.entryID)
                            }
                        }
                        .draggable(FoodEntryDragPayload(id: row.entryID))
                        .dropDestination(for: FoodEntryDragPayload.self) {
                            payloads, _ in
                            guard let payload = payloads.first else {
                                return false
                            }
                            return drop(payload.id, onto: row.entryID)
                        }
                    }
                }
            }
            if let note = meal.note {
                // Rendered, like every other place a note is read: what is
                // typed into the sheet is Markdown, and a `#Tom` left with its
                // hash here says the note is raw text — which it is not, since
                // that tag files the day in the journal.
                MarkdownText(markdown: note, hidesTagHashes: true)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func entry(for id: PersistentIdentifier) -> FoodEntry? {
        entries.first { $0.persistentModelID == id }
    }

    /// What the cursor's row is painted with.
    ///
    /// Not `.selection`, which was here first and came out grey: that style
    /// picks between the emphasised and unemphasised selection colours, and
    /// outside a `List` SwiftUI has nothing telling it this row is the focused
    /// one — so it always chose the quiet half of the pair. The meals are a
    /// `Grid`, not a list, and there is no list to inherit the answer from.
    ///
    /// The accent colour, then, but laid on thin: a solid selection blue wants
    /// white labels on it, and the row carries a starred favourite and a line
    /// of figures that are read at a glance. Tinted, the band says "here"
    /// without repainting everything inside it.
    private static let cursorFill = AnyShapeStyle(.tint.opacity(0.28))

    private func moveCursor(by delta: Int) -> KeyPress.Result {
        guard !isPresentingModal else { return .ignored }
        cursor = DayCursorModel.move(
            from: cursor, by: delta, rowCounts: currentRowCounts
        )
        return .handled
    }

    /// The row a new food lands under in this meal, or nil to append.
    ///
    /// Only when the cursor is on a row of *that* meal: adding to a meal from
    /// its own `+` while the cursor rests three meals below must not scatter
    /// the food into the meal one happened to be reading.
    private func anchor(in slot: MealSlot) -> FoodEntry? {
        guard let entry = cursorEntry,
              entry.mealSlot?.persistentModelID == slot.persistentModelID
        else { return nil }
        return entry
    }

    /// Where an entry sits on screen, in the cursor's coordinates.
    ///
    /// The same ordering the rows are drawn in — slots by `sortOrder`, rows by
    /// theirs — because a cursor that disagrees with the grid points at the
    /// wrong food.
    private func position(of id: PersistentIdentifier) -> DayCursor? {
        let ordered = slots.sorted { $0.sortOrder < $1.sortOrder }
        guard let entry = entry(for: id),
              let slotID = entry.mealSlot?.persistentModelID,
              let mealIndex = ordered.firstIndex(where: {
                  $0.persistentModelID == slotID
              })
        else { return nil }
        let rows = entries
            .filter {
                $0.dateKeyRaw == entry.dateKeyRaw
                    && $0.mealSlot?.persistentModelID == slotID
            }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard let rowIndex = rows.firstIndex(where: {
            $0.persistentModelID == id
        }) else { return nil }
        return DayCursor(mealIndex: mealIndex, rowIndex: rowIndex)
    }

    private func slotModel(for id: PersistentIdentifier) -> MealSlot? {
        slots.first { $0.persistentModelID == id }
    }

    private func move(_ id: PersistentIdentifier, direction: Int) {
        guard let entry = entry(for: id) else { return }
        do {
            try NutritionJournal.move(entry, direction: direction, in: modelContext)
        } catch {
            writeFailureMessage =
                "Le déplacement n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }

    /// Reorders by drag: the dragged entry lands right after the row it was
    /// dropped on. Same-meal only — `placeEntry` refuses the rest, and
    /// returning false lets the system animate the rejection.
    private func drop(
        _ draggedID: PersistentIdentifier, onto targetID: PersistentIdentifier
    ) -> Bool {
        guard draggedID != targetID,
              let dragged = entry(for: draggedID),
              let target = entry(for: targetID)
        else { return false }
        guard dragged.mealSlot?.persistentModelID
            == target.mealSlot?.persistentModelID
        else { return false }
        do {
            try NutritionJournal.placeEntry(dragged, after: target, in: modelContext)
            return true
        } catch {
            writeFailureMessage =
                "Le déplacement n'a pas pu être enregistré. \(error.localizedDescription)"
            return false
        }
    }

    private func toggleFavorite(_ id: PersistentIdentifier) {
        guard let entry = entry(for: id) else { return }
        do {
            try NutritionJournal.toggleFavorite(for: entry, in: modelContext)
        } catch {
            writeFailureMessage =
                "Le favori n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }

    private func deleteEntry(_ id: PersistentIdentifier) {
        guard let entry = entry(for: id) else { return }
        do {
            try NutritionJournal.delete(entry, in: modelContext)
        } catch {
            writeFailureMessage =
                "Votre suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    private func setDayType(_ dayType: DayType?) {
        do {
            try NutritionJournal.setDayType(dayType, for: dateKey, in: modelContext)
        } catch {
            writeFailureMessage =
                "Le jour-type n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }

    private func saveRecipe() {
        guard let slot = savingRecipeSlot else { return }
        let name = recipeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            writeFailureMessage = "Donnez un nom à la recette pour l'enregistrer."
            return
        }
        do {
            try NutritionJournal.saveMealAsRecipe(
                named: name, dateKey: dateKey, slot: slot, in: modelContext
            )
        } catch {
            writeFailureMessage =
                "La recette n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Aucun journal alimentaire",
                systemImage: "fork.knife",
                description: Text(
                    "Importez vos données suivinut, ou démarrez un journal "
                    + "vierge. L'import reste possible ensuite dans "
                    + "Réglages → Nutrition tant que le journal est vide."
                )
            )
            HStack {
                Button("Importer depuis suivinut…") { chooseAndImport() }
                    .buttonStyle(.borderedProminent)
                Button("Commencer sans importer") { seed() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseAndImport() {
        importMessage = SuivinutImportFlow.chooseAndImport(
            container: modelContext.container
        )
    }

    private func seed() {
        do {
            try NutritionSeed.runIfEmpty(in: modelContext)
        } catch {
            importMessage =
                "La création du journal a échoué : \(error.localizedDescription)"
        }
    }
}
