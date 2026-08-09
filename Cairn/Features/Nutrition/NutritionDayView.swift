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
    @State private var cursor: DayCursor?
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
            || noteTargetSlot != nil
    }

    /// Rows per meal for the CURRENT day — the cursor's coordinate system.
    /// Recomputed on demand: cheap, and always consistent with what the
    /// screen shows.
    private var currentRowCounts: [Int] {
        let dayEntries = entries.filter { $0.dateKeyRaw == dateKey.raw }
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
                $0.dateKeyRaw == dateKey.raw
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
                dateKey = dateKey.advanced(by: -1)
                return true
            case .dayForward:
                dateKey = dateKey.advanced(by: 1)
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
                    deleteEntry(entry.persistentModelID)
                    cursor = DayCursorModel.clamp(
                        cursor, rowCounts: currentRowCounts
                    )
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
                if dateKey != DateKey(Date()) {
                    dateKey = DateKey(Date())
                    return true
                }
                return onCommand(command)
            default:
                return onCommand(command)
            }
        }
        .onKeyPress(.leftArrow) {
            guard !isPresentingModal else { return .ignored }
            dateKey = dateKey.advanced(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isPresentingModal else { return .ignored }
            dateKey = dateKey.advanced(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !isPresentingModal, let entry = cursorEntry else {
                return .ignored
            }
            editingEntry = entry
            return .handled
        }
        .onChange(of: dateKey) { _, _ in
            cursor = DayCursorModel.clamp(cursor, rowCounts: currentRowCounts)
        }
        .onChange(of: entries.count) { _, _ in
            cursor = DayCursorModel.clamp(cursor, rowCounts: currentRowCounts)
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
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $addTargetSlot) { slot in
            AddFoodSheet(slot: slot, dateKey: dateKey)
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
        }
    }

    private func mealSection(
        _ meal: NutritionDayModel.Meal, mealIndex: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meal.slotName).font(.headline)
                Spacer()
                Text(mealFigure(meal))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            }
            .padding(.horizontal, 6)
            .background(
                // `.selection` rather than `.quaternary`: the cursor is a
                // selection, and the system's own row-selection style is the
                // one contrast the eye already knows.
                cursor == DayCursor(mealIndex: mealIndex, rowIndex: nil)
                    ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 4)
            )
            if meal.rows.isEmpty {
                Text("Rien de consigné")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                        Text("Aliment")
                        Text("g").gridColumnAlignment(.trailing)
                        Text("kcal").gridColumnAlignment(.trailing)
                        Text("P").gridColumnAlignment(.trailing)
                        Text("G").gridColumnAlignment(.trailing)
                        Text("L").gridColumnAlignment(.trailing)
                    }
                    .font(.caption)
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
                            Text("\(Int(row.grams.rounded()))")
                            Text("\(Int(row.macros.kcal.rounded()))")
                            Text("\(Int(row.macros.protein.rounded()))")
                            Text("\(Int(row.macros.carbs.rounded()))")
                            Text("\(Int(row.macros.fat.rounded()))")
                        }
                        // `monospacedDigit()` is a `Text` method; on a row
                        // the font modifier carries the same trait.
                        .font(.body.monospacedDigit())
                        .background(
                            cursor == DayCursor(
                                mealIndex: mealIndex, rowIndex: rowIndex
                            )
                                ? AnyShapeStyle(.selection)
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .contextMenu {
                            Button("Éditer…") {
                                editingEntry = entry(for: row.entryID)
                            }
                            Button("Monter") { move(row.entryID, direction: -1) }
                            Button("Descendre") { move(row.entryID, direction: 1) }
                            Button("Basculer favori") { toggleFavorite(row.entryID) }
                            Divider()
                            Button("Supprimer", role: .destructive) {
                                deleteEntry(row.entryID)
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
                Text(note)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "612 / 655 kcal" when the meal has an adaptive target, plain total
    /// otherwise — the header answers "how am I doing on this meal" at a
    /// glance.
    private func mealFigure(_ meal: NutritionDayModel.Meal) -> String {
        let consumed = Int(meal.consumed.kcal.rounded())
        guard let target = meal.target else { return "\(consumed) kcal" }
        return "\(consumed) / \(Int(target.kcal.rounded())) kcal"
    }

    private func entry(for id: PersistentIdentifier) -> FoodEntry? {
        entries.first { $0.persistentModelID == id }
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
