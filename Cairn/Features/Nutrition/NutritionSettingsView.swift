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
    @State private var updater = CatalogUpdater()
    @State private var catalogStatus = ""

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
                switch updater.phase {
                case .downloading(let megabytes, let total):
                    HStack {
                        ProgressView(
                            value: total.flatMap { $0 > 0 ? min(megabytes / $0, 1) : nil } ?? 0
                        )
                        Text(downloadLabel(megabytes: megabytes, total: total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Annuler") { updater.cancel() }
                    }
                case .building(let kept):
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Construction… \(kept) produits retenus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Annuler") { updater.cancel() }
                    }
                case .failed(let message):
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Button("Mettre à jour le catalogue") { updater.start() }
                case .done, .idle:
                    Button("Mettre à jour le catalogue") { updater.start() }
                }
            }
            .onChange(of: updater.phase) { _, newPhase in
                if case .done = newPhase { refreshCatalogStatus() }
            }

            if entries.isEmpty {
                Section("Données") {
                    Button("Importer depuis suivinut…") { chooseAndImport() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCatalogStatus() }
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

    /// Opens SQLite and runs a COUNT(*) — real I/O, not cheap enough to
    /// re-derive on every `body` evaluation. Called from `.onAppear` and
    /// when a build finishes, never from `body` itself: `updater.phase`
    /// changes up to once per frame during a download, and this used to be
    /// a computed property read directly from `body`, hitting the
    /// main-thread database every one of those frames for minutes.
    private func refreshCatalogStatus() {
        guard let catalog = FoodCatalog.openDefault(),
              let count = try? catalog.productCount()
        else {
            catalogStatus = "Aucun catalogue — l'import suivinut en copie un, "
                + "ou téléchargez-le ci-dessous."
            return
        }
        // `try?` on a call that already returns `String?` flattens to a
        // single `String?` since SE-0230 (Swift 5+), so one `if let`
        // unwraps it — a second `, let importedAt` (as sketched in the
        // brief, guarding against a double optional) doesn't compile: the
        // first binding already produces a non-optional `String`.
        if let importedAt = try? catalog.importedAt() {
            catalogStatus = "\(count) produits Open Food Facts — importé le \(importedAt)."
        } else {
            catalogStatus = "\(count) produits Open Food Facts."
        }
    }

    private func downloadLabel(megabytes: Double, total: Double?) -> String {
        let done = Format.typedNumber(megabytes)
        guard let total else { return "\(done) Mo téléchargés" }
        return "\(done) / \(Format.typedNumber(total)) Mo"
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
