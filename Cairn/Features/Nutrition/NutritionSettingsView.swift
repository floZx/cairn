// Cairn/Features/Nutrition/NutritionSettingsView.swift
import SwiftUI
import SwiftData
import AppKit

/// Everything the nutrition journal is configured by: macro targets, day
/// types, per-meal shares, catalog status, and the one-shot suivinut import.
struct NutritionSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(NutritionSettings.proteinTargetKey)
    private var proteinTarget = NutritionSettings.defaultProteinTargetG
    @AppStorage(NutritionSettings.fatTargetKey)
    private var fatTarget = NutritionSettings.defaultFatTargetG
    @AppStorage(NutritionSettings.weightGoalKey)
    private var weightGoal = NutritionSettings.defaultWeightGoalKg
    @Query(sort: \DayType.sortOrder) private var dayTypes: [DayType]
    @Query(sort: \MealSlot.sortOrder) private var slots: [MealSlot]
    @Query private var entries: [FoodEntry]
    @State private var importMessage: String?
    @State private var writeFailureMessage: String?

    var body: some View {
        Form {
            Section("Cibles") {
                TextField(
                    "Protéines (g/j)", value: $proteinTarget, format: .number
                )
                TextField("Lipides (g/j)", value: $fatTarget, format: .number)
                TextField(
                    "Objectif de poids (kg)", value: $weightGoal, format: .number
                )
            }

            Section("Jours-types") {
                ForEach(dayTypes) { dayType in
                    dayTypeRow(dayType)
                }
                Button("Ajouter un jour-type") { addDayType() }
            }

            Section {
                ForEach(slots) { slot in
                    slotRow(slot)
                }
            } header: {
                Text("Répartition des repas")
            } footer: {
                // Green only at exactly 100: the plan's shares are meant to
                // cover the day, and both gaps and overshoot mislead the
                // adaptive targets.
                Text("Total : \(totalPct) %")
                    .foregroundStyle(totalPct == 100 ? .green : .secondary)
                    .monospacedDigit()
            }

            Section("Catalogue") {
                Text(catalogStatus)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Section("Données") {
                    Button("Importer depuis suivinut…") { chooseAndImport() }
                }
            }
        }
        .formStyle(.grouped)
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

    // MARK: - Rows

    private func dayTypeRow(_ dayType: DayType) -> some View {
        @Bindable var dayType = dayType
        return HStack {
            TextField("Nom", text: $dayType.name)
                .onSubmit { save() }
            TextField(
                "kcal", value: $dayType.kcalTarget, format: .number
            )
            .frame(width: 80)
            .onSubmit { save() }
            .monospacedDigit()
            Button {
                delete(dayType)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Supprimer ce jour-type")
        }
    }

    private func slotRow(_ slot: MealSlot) -> some View {
        @Bindable var slot = slot
        return HStack {
            Text(slot.name)
            Spacer()
            TextField("%", value: $slot.targetPct, format: .number)
                .frame(width: 60)
                .onSubmit { save() }
                .monospacedDigit()
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    private var totalPct: Int {
        slots.map(\.targetPct).reduce(0, +)
    }

    private var catalogStatus: String {
        guard let catalog = FoodCatalog.openDefault(),
              let count = try? catalog.productCount()
        else {
            return "Aucun catalogue — l'import suivinut en copie un, "
                + "le téléchargement direct arrive dans une prochaine version."
        }
        return "\(count) produits Open Food Facts."
    }

    // MARK: - Actions

    private func addDayType() {
        do {
            _ = try NutritionJournal.addDayType(
                named: "Nouveau", kcalTarget: 2000, in: modelContext
            )
        } catch {
            writeFailureMessage =
                "Le jour-type n'a pas pu être créé. \(error.localizedDescription)"
        }
    }

    private func delete(_ dayType: DayType) {
        do {
            try NutritionJournal.deleteDayType(dayType, in: modelContext)
        } catch {
            writeFailureMessage =
                "La suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            writeFailureMessage =
                "Votre modification n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    // MARK: - Import

    private func chooseAndImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choisir le journal.db de suivinut"
        let iCloudFolder = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/suivinut")
        if FileManager.default.fileExists(atPath: iCloudFolder.path) {
            panel.directoryURL = iCloudFolder
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importJournal(from: url)
    }

    private func importJournal(from url: URL) {
        // A context of its own: `run` rolls back on failure, and rolling back
        // the shared main context would also discard whatever edits the
        // settings fields hold at that moment.
        let importContext = ModelContext(modelContext.container)
        do {
            let summary = try SuivinutImporter(context: importContext)
                .run(journalPath: url.path)
            if let value = summary.proteinTargetG { proteinTarget = value }
            if let value = summary.fatTargetG { fatTarget = value }
            if let value = summary.weightGoalKg { weightGoal = value }
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
}
