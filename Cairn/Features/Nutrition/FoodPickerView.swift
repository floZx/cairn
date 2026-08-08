// Cairn/Features/Nutrition/FoodPickerView.swift
import SwiftUI
import SwiftData

/// What the picker hands back: everything an entry or a recipe item needs.
struct FoodPick: Equatable {
    var foodName: String
    var kcal100: Double
    var protein100: Double
    var carbs100: Double
    var fat100: Double
    var grams: Double
    var productCode: String?
}

/// Search + favorites + manual entry, ending in one `FoodPick`. Owns no
/// persistence: the caller decides whether the pick becomes a journal entry
/// or a recipe item.
struct FoodPickerView: View {
    let onPick: (FoodPick) -> Void   // called on "Ajouter"

    @Environment(\.modelContext) private var modelContext

    private enum Mode: Hashable {
        case search
        case favorites
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

    @Query(sort: \FavoriteFood.foodName) private var favorites: [FavoriteFood]
    @State private var selectedFavorite: FavoriteFood?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $mode) {
                Text("Recherche").tag(Mode.search)
                Text("Favoris").tag(Mode.favorites)
                Text("Manuel").tag(Mode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .search: searchPane
            case .favorites: favoritesPane
            case .manual: manualPane
            }

            HStack {
                Spacer()
                Button("Ajouter") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
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

    // MARK: - Favorites

    private var favoritesPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "Aucun favori",
                    systemImage: "star",
                    description: Text(
                        "L'étoile d'une ligne du journal ajoute l'aliment ici."
                    )
                )
            } else {
                List(favorites, selection: favoriteSelection) { favorite in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favorite.foodName).lineLimit(1)
                        Text(favoriteSubtitle(favorite))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(favorite.persistentModelID)
                    .contextMenu {
                        Button("Retirer des favoris", role: .destructive) {
                            remove(favorite)
                        }
                    }
                }
                .frame(minHeight: 180)
                if selectedFavorite != nil {
                    gramsRow(kcal100: selectedFavorite?.kcal100 ?? 0)
                }
            }
        }
    }

    private var favoriteSelection: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedFavorite?.persistentModelID },
            set: { id in
                selectedFavorite = favorites.first { $0.persistentModelID == id }
                // The favorite carries its usual serving; prefill it so the
                // common case is two clicks, not a retype.
                if let grams = selectedFavorite?.grams { self.grams = grams }
            }
        )
    }

    private func favoriteSubtitle(_ favorite: FavoriteFood) -> String {
        "\(Int(favorite.grams.rounded())) g — "
            + "\(Int((favorite.kcal100 * favorite.grams / 100).rounded())) kcal"
    }

    private func remove(_ favorite: FavoriteFood) {
        try? NutritionJournal.removeFavorite(favorite, in: modelContext)
        if selectedFavorite?.persistentModelID == favorite.persistentModelID {
            selectedFavorite = nil
        }
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
        case .favorites: return selectedFavorite != nil
        case .manual:
            // Negative per-100 g values are typos, and they would silently
            // distort every gauge of the day.
            return !manualName.trimmingCharacters(in: .whitespaces).isEmpty
                && manualKcal >= 0 && manualProtein >= 0
                && manualCarbs >= 0 && manualFat >= 0
        }
    }

    private func confirm() {
        switch mode {
        case .search:
            guard let selected else { return }
            onPick(FoodPick(
                foodName: selected.name, kcal100: selected.kcal100,
                protein100: selected.protein100, carbs100: selected.carbs100,
                fat100: selected.fat100, grams: grams,
                productCode: selected.code
            ))
        case .favorites:
            guard let favorite = selectedFavorite else { return }
            onPick(FoodPick(
                foodName: favorite.foodName, kcal100: favorite.kcal100,
                protein100: favorite.protein100, carbs100: favorite.carbs100,
                fat100: favorite.fat100, grams: grams,
                productCode: favorite.productCode
            ))
        case .manual:
            onPick(FoodPick(
                foodName: manualName.trimmingCharacters(in: .whitespaces),
                kcal100: manualKcal, protein100: manualProtein,
                carbs100: manualCarbs, fat100: manualFat, grams: grams,
                productCode: nil
            ))
        }
    }
}
