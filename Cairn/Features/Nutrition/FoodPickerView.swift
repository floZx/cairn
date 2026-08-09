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
    @State private var results: [FoodSearch.Hit] = []
    @State private var searchErrorMessage: String?
    @State private var selected: FoodSearch.Hit?
    /// The distinct foods most recently logged, fetched once per presentation:
    /// with an empty search field they are the list — the suivinut behaviour,
    /// because the next food is usually one of the last thirty.
    @State private var recents: [FoodSearch.Hit] = []
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

    @FocusState private var searchFocused: Bool
    @FocusState private var gramsFocused: Bool

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
        .onAppear {
            catalog = FoodCatalog.openDefault()
            recents = fetchRecents()
            runSearch(query)
            searchFocused = true
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .search { searchFocused = true }
        }
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
                TextField(
                    "Rechercher un aliment (vide : favoris et derniers utilisés)",
                    text: $query
                )
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onChange(of: query) { _, newValue in
                        runSearch(newValue)
                    }
                    .onSubmit {
                        // Return in the search field: take the first hit and
                        // jump to the quantity — type, Return, done. The
                        // suivinut rhythm.
                        if selected == nil { select(results.first) }
                        if selected != nil { gramsFocused = true }
                    }
                List(results, selection: resultSelection) { hit in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if hit.isFavorite {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                            }
                            Text(hit.name).lineLimit(1)
                        }
                        Text(subtitle(of: hit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(hit.id)
                }
                .frame(minHeight: 180)
                if let searchErrorMessage {
                    Text(searchErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if let selected {
                    gramsRow(kcal100: selected.kcal100)
                }
            }
        }
    }

    /// Selection carried by the hit's id — `Hit` is a plain value and the
    /// list wants a stable `Hashable` tag.
    private var resultSelection: Binding<String?> {
        Binding(
            get: { selected?.id },
            set: { id in select(results.first { $0.id == id }) }
        )
    }

    private func select(_ hit: FoodSearch.Hit?) {
        selected = hit
        // A favorite carries its usual serving; prefill it so the common
        // case is type, Return, Return.
        if let favoriteGrams = hit?.favoriteGrams { grams = favoriteGrams }
    }

    private func runSearch(_ text: String) {
        let favoriteHits = favorites.map { favorite in
            FoodSearch.Hit(
                id: "fav:\(favorite.foodName)|\(favorite.productCode ?? "")",
                name: favorite.foodName, brands: "",
                kcal100: favorite.kcal100, protein100: favorite.protein100,
                carbs100: favorite.carbs100, fat100: favorite.fat100,
                productCode: favorite.productCode,
                favoriteGrams: favorite.grams
            )
        }
        var catalogHits: [FoodSearch.Hit] = []
        if let catalog, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                catalogHits = try catalog.search(text).map { product in
                    FoodSearch.Hit(
                        id: "cat:\(product.code)",
                        name: product.name, brands: product.brands,
                        kcal100: product.kcal100, protein100: product.protein100,
                        carbs100: product.carbs100, fat100: product.fat100,
                        productCode: product.code, favoriteGrams: nil
                    )
                }
                searchErrorMessage = nil
            } catch {
                // A broken catalog must say so — a silently empty list reads
                // as « no result », which is a different fact.
                searchErrorMessage =
                    "La recherche a échoué : \(error.localizedDescription)"
            }
        } else {
            searchErrorMessage = nil
        }
        results = FoodSearch.assemble(
            query: text, favorites: favoriteHits, recents: recents,
            catalog: catalogHits
        )
        if let selected, !results.contains(selected) {
            self.selected = nil
        }
    }

    /// The last thirty distinct foods, newest day first — suivinut's
    /// `recent_foods`. Fetched wide then deduplicated here: SwiftData has no
    /// GROUP BY, and three hundred rows is nothing.
    private func fetchRecents() -> [FoodSearch.Hit] {
        var descriptor = FetchDescriptor<FoodEntry>(
            sortBy: [
                SortDescriptor(\.dateKeyRaw, order: .reverse),
                SortDescriptor(\.sortOrder, order: .reverse),
            ]
        )
        descriptor.fetchLimit = 300
        guard let entries = try? modelContext.fetch(descriptor) else { return [] }
        var seen = Set<String>()
        var hits: [FoodSearch.Hit] = []
        for entry in entries {
            let key = "\(entry.foodName)|\(entry.productCode ?? "")"
            guard seen.insert(key).inserted else { continue }
            hits.append(FoodSearch.Hit(
                id: "recent:\(key)",
                name: entry.foodName, brands: "",
                kcal100: entry.kcal100, protein100: entry.protein100,
                carbs100: entry.carbs100, fat100: entry.fat100,
                productCode: entry.productCode, favoriteGrams: nil
            ))
            if hits.count == 30 { break }
        }
        return hits
    }

    private func subtitle(of hit: FoodSearch.Hit) -> String {
        let macros = "\(Int(hit.kcal100.rounded())) kcal · "
            + "P \(Int(hit.protein100.rounded())) · "
            + "G \(Int(hit.carbs100.rounded())) · "
            + "L \(Int(hit.fat100.rounded())) /100 g"
        return hit.brands.isEmpty ? macros : "\(hit.brands) — \(macros)"
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
                .focused($gramsFocused)
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
                productCode: selected.productCode
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
