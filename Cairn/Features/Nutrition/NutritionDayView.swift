// Cairn/Features/Nutrition/NutritionDayView.swift
import SwiftUI
import SwiftData
import AppKit

/// The daily food journal — Cairn's take on suivinut's Day screen. Read-only
/// in phase 1: navigation, targets and totals; entry editing arrives with
/// phase 2.
struct NutritionDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealSlot.sortOrder) private var slots: [MealSlot]
    @Query private var days: [NutritionDay]
    @Query private var entries: [FoodEntry]
    @Query private var notes: [MealNote]
    @AppStorage(NutritionSettings.proteinTargetKey)
    private var proteinTarget = NutritionSettings.defaultProteinTargetG
    @AppStorage(NutritionSettings.fatTargetKey)
    private var fatTarget = NutritionSettings.defaultFatTargetG
    @AppStorage(NutritionSettings.weightGoalKey)
    private var weightGoal = NutritionSettings.defaultWeightGoalKg
    @State private var dateKey = DateKey(Date())
    @State private var importMessage: String?
    @State private var addTargetSlot: MealSlot?
    @State private var editingEntry: FoodEntry?
    @State private var writeFailureMessage: String?
    // Sorted the way suivinut lists day types: by target then name, so the
    // menu reads from rest day to biggest day.
    @Query(sort: [
        SortDescriptor(\DayType.kcalTarget), SortDescriptor(\DayType.name),
    ]) private var dayTypes: [DayType]

    var body: some View {
        Group {
            if slots.isEmpty {
                onboarding
            } else {
                journal
            }
        }
        .alert(
            "Import suivinut",
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

    // MARK: - Journal

    private var journal: some View {
        // Filtered in memory, the way every other view applies
        // `ActivityFilter`: the journal holds hundreds of entries, not
        // enough to justify dynamic predicates.
        let dayEntries = entries.filter { $0.dateKeyRaw == dateKey.raw }
        let day = days.first { $0.dateKeyRaw == dateKey.raw }
        let dayNotes = notes.filter { $0.dateKeyRaw == dateKey.raw }
        let model = NutritionDayModel.compute(
            entries: dayEntries, slots: slots, notes: dayNotes,
            dayType: day?.dayType,
            proteinTargetG: proteinTarget, fatTargetG: fatTarget
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(model)
                summary(model)
                Divider()
                ForEach(model.meals, id: \.slotID) { meal in
                    mealSection(meal)
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

    private func mealSection(_ meal: NutritionDayModel.Meal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meal.slotName).font(.headline)
                Spacer()
                Text(mealFigure(meal))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    addTargetSlot = slots.first {
                        $0.persistentModelID == meal.slotID
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Ajouter un aliment à \(meal.slotName)")
            }
            if meal.rows.isEmpty {
                Text("Rien de consigné")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Aliment")
                        Text("g").gridColumnAlignment(.trailing)
                        Text("kcal").gridColumnAlignment(.trailing)
                        Text("P").gridColumnAlignment(.trailing)
                        Text("G").gridColumnAlignment(.trailing)
                        Text("L").gridColumnAlignment(.trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(meal.rows, id: \.entryID) { row in
                        GridRow {
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
                        .contextMenu {
                            Button("Éditer…") {
                                editingEntry = entry(for: row.entryID)
                            }
                            Button("Monter") { move(row.entryID, direction: -1) }
                            Button("Descendre") { move(row.entryID, direction: 1) }
                            Divider()
                            Button("Supprimer", role: .destructive) {
                                deleteEntry(row.entryID)
                            }
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

    private func move(_ id: PersistentIdentifier, direction: Int) {
        guard let entry = entry(for: id) else { return }
        do {
            try NutritionJournal.move(entry, direction: direction, in: modelContext)
        } catch {
            writeFailureMessage =
                "Le déplacement n'a pas pu être enregistré. \(error.localizedDescription)"
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

    // MARK: - Onboarding

    private var onboarding: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Aucun journal alimentaire",
                systemImage: "fork.knife",
                description: Text(
                    "Importez vos données suivinut, ou démarrez un journal vierge."
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choisir le journal.db de suivinut"
        // Where the living journal actually is — the iCloud folder shared
        // with the suivinut TUI. Falling back to home if it does not exist.
        let iCloudFolder = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/suivinut")
        if FileManager.default.fileExists(atPath: iCloudFolder.path) {
            panel.directoryURL = iCloudFolder
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importJournal(from: url)
    }

    private func importJournal(from url: URL) {
        do {
            let summary = try SuivinutImporter(context: modelContext)
                .run(journalPath: url.path)
            if let value = summary.proteinTargetG { proteinTarget = value }
            if let value = summary.fatTargetG { fatTarget = value }
            if let value = summary.weightGoalKg { weightGoal = value }
            // Best effort: a missing catalog is normal (phase 5 downloads
            // one), so only a found-but-uncopyable catalog would matter, and
            // even that must not fail an import that already succeeded.
            _ = try? SuivinutImporter.copyCatalog(
                nextTo: url,
                to: URL.applicationSupportDirectory.appending(path: "Cairn")
            )
            importMessage =
                "\(summary.entries) aliments, \(summary.weights) pesées et "
                + "\(summary.recipes) recettes importés."
        } catch {
            importMessage =
                "L'import a échoué : \(error.localizedDescription) "
                + "Rien n'a été modifié."
        }
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
