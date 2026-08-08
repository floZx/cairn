// Cairn/Features/Nutrition/AddFoodSheet.swift
import SwiftUI
import SwiftData

/// Adding one food to one meal: offline catalog search, or manual entry
/// for anything the catalog does not know. The per-100 g values are copied
/// onto the entry at save time — the journal never references the catalog
/// after this sheet closes.
struct AddFoodSheet: View {
    let slot: MealSlot
    let dateKey: DateKey

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable {
        case search
        case manual
    }

    @State private var mode: Mode = .search
    @State private var query = ""
    @State private var results: [FoodCatalog.Product] = []
    @State private var selected: FoodCatalog.Product?
    @State private var grams = 100.0
    @State private var manualName = ""
    @State private var manualKcal = 0.0
    @State private var manualProtein = 0.0
    @State private var manualCarbs = 0.0
    @State private var manualFat = 0.0
    // Opened once per presentation: the file cannot change under the sheet,
    // and reopening per keystroke would reparse the FTS index needlessly.
    @State private var catalog: FoodCatalog?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajouter à \(slot.name)")
                .font(.headline)
            Picker("", selection: $mode) {
                Text("Recherche").tag(Mode.search)
                Text("Manuel").tag(Mode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .search: searchPane
            case .manual: manualPane
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ajouter") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 440)
        .onAppear { catalog = FoodCatalog.openDefault() }
    }

    // MARK: - Search

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if catalog == nil {
                ContentUnavailableView(
                    "Catalogue introuvable",
                    systemImage: "magnifyingglass",
                    description: Text(
                        "La recherche d'aliments demande le catalogue Open "
                        + "Food Facts. En attendant, la saisie manuelle "
                        + "reste disponible."
                    )
                )
            } else {
                TextField("Rechercher un aliment", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, newValue in
                        runSearch(newValue)
                    }
                List(results, id: \.code, selection: resultSelection) { product in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name).lineLimit(1)
                        Text(subtitle(of: product))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(product.code)
                }
                .frame(minHeight: 180)
                if let selected {
                    gramsRow(kcal100: selected.kcal100)
                }
            }
        }
    }

    /// Selection carried by product code — `Product` is a plain value and
    /// the list wants a stable `Hashable` tag.
    private var resultSelection: Binding<String?> {
        Binding(
            get: { selected?.code },
            set: { code in selected = results.first { $0.code == code } }
        )
    }

    private func runSearch(_ text: String) {
        guard let catalog else { return }
        // A failed read degrades to an empty list: the catalog is optional
        // comfort, never a crash.
        results = (try? catalog.search(text)) ?? []
        if let selected, !results.contains(selected) {
            self.selected = nil
        }
    }

    private func subtitle(of product: FoodCatalog.Product) -> String {
        let macros = "\(Int(product.kcal100.rounded())) kcal · "
            + "P \(Int(product.protein100.rounded())) · "
            + "G \(Int(product.carbs100.rounded())) · "
            + "L \(Int(product.fat100.rounded())) /100 g"
        return product.brands.isEmpty ? macros : "\(product.brands) — \(macros)"
    }

    // MARK: - Manual

    private var manualPane: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Aliment")
                TextField("Nom", text: $manualName)
                    .textFieldStyle(.roundedBorder)
                    .gridCellColumns(3)
            }
            GridRow {
                Text("kcal /100 g")
                TextField("kcal", value: $manualKcal, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text("Protéines /100 g")
                TextField("g", value: $manualProtein, format: .number)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Glucides /100 g")
                TextField("g", value: $manualCarbs, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text("Lipides /100 g")
                TextField("g", value: $manualFat, format: .number)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Quantité")
                TextField("g", value: $grams, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text(manualPreview)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .gridCellColumns(2)
            }
        }
    }

    private var manualPreview: String {
        "\(Int((manualKcal * grams / 100).rounded())) kcal"
    }

    // MARK: - Shared grams row and add

    private func gramsRow(kcal100: Double) -> some View {
        HStack(spacing: 8) {
            Text("Quantité")
            TextField("g", value: $grams, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("g")
            Spacer()
            Text("\(Int((kcal100 * grams / 100).rounded())) kcal")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var canAdd: Bool {
        guard grams > 0 else { return false }
        switch mode {
        case .search: return selected != nil
        case .manual:
            return !manualName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func add() {
        do {
            switch mode {
            case .search:
                guard let selected else { return }
                try NutritionJournal.addEntry(
                    in: modelContext, dateKey: dateKey, slot: slot,
                    foodName: selected.name, kcal100: selected.kcal100,
                    protein100: selected.protein100,
                    carbs100: selected.carbs100, fat100: selected.fat100,
                    grams: grams, productCode: selected.code
                )
            case .manual:
                try NutritionJournal.addEntry(
                    in: modelContext, dateKey: dateKey, slot: slot,
                    foodName: manualName.trimmingCharacters(in: .whitespaces),
                    kcal100: manualKcal, protein100: manualProtein,
                    carbs100: manualCarbs, fat100: manualFat, grams: grams
                )
            }
            dismiss()
        } catch {
            errorMessage =
                "Votre ajout n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }
}
