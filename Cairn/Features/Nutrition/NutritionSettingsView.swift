// Cairn/Features/Nutrition/NutritionSettingsView.swift
import SwiftUI
import SwiftData

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
    @State private var showsRecipesManager = false
    @State private var showsFavoritesManager = false

    var body: some View {
        Form {
            Section("Cibles") {
                DecimalField(placeholder: "Protéines (g/j)", value: $proteinTarget)
                DecimalField(placeholder: "Lipides (g/j)", value: $fatTarget)
                DecimalField(
                    placeholder: "Objectif de poids (kg)", value: $weightGoal
                )
            }

            Section {
                ForEach(Array(dayTypes.enumerated()), id: \.element) {
                    index, dayType in
                    dayTypeRow(dayType, index: index)
                }
                Button("Ajouter un jour-type") { addDayType() }
            } header: {
                Text("Jours-types")
            } footer: {
                Text("L'ordre est celui du menu de jour-type du journal.")
            }

            Section {
                Button("Gérer les recettes…") { showsRecipesManager = true }
                Button("Gérer les favoris…") { showsFavoritesManager = true }
            } header: {
                Text("Bibliothèque")
            } footer: {
                Text(
                    "Les recettes se créent depuis un repas rempli, les favoris "
                    + "avec l'étoile d'une ligne du journal."
                )
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
        .sheet(isPresented: $showsRecipesManager) { RecipesManagerSheet() }
        .sheet(isPresented: $showsFavoritesManager) { FavoritesManagerSheet() }
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

    private func dayTypeRow(_ dayType: DayType, index: Int) -> some View {
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
            // Arrows rather than drag: the row is two text fields wide, and a
            // drag started on one of them is someone selecting text.
            Button {
                move(dayType, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Monter ce jour-type")
            Button {
                move(dayType, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == dayTypes.count - 1)
            .help("Descendre ce jour-type")
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

    private func move(_ dayType: DayType, by offset: Int) {
        do {
            try NutritionJournal.moveDayType(dayType, by: offset, in: modelContext)
        } catch {
            writeFailureMessage =
                "L'ordre n'a pas pu être enregistré. \(error.localizedDescription)"
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
        importMessage = SuivinutImportFlow.chooseAndImport(
            container: modelContext.container
        )
    }
}
