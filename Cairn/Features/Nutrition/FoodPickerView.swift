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
    /// Nulles quand la source ne les connaît pas — voir `FoodEntry.fiber100`.
    var fiber100: Double?
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
    /// Bumped by every search, so the list knows to go back to its first row.
    ///
    /// A counter rather than something derived from `results`: two searches
    /// running one after the other can hand back the very same rows — a
    /// letter that narrows nothing — and the list still has to scroll up.
    @State private var searchGeneration = 0
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
                        // Return in the search field: take whatever the arrows
                        // are pointing at, or the first hit when they have not
                        // been used, and jump to the quantity — type, Return,
                        // done. The suivinut rhythm.
                        if selected == nil { select(results.first) }
                        if selected != nil { gramsFocused = true }
                    }
                    // The arrows walk the results without leaving the field,
                    // so the search stays editable all the way down the list.
                    // They have to be caught here rather than left to the list:
                    // the field holds the focus while one types, and an arrow
                    // key was moving the insertion point through "riz".
                    //
                    // Plain `j` and `k` cannot serve in a search field, where
                    // they are two perfectly good letters to type — "jambon",
                    // "kiwi". Held with control they are no longer letters,
                    // so the vim pair works here too, beside the arrows.
                    .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                    .onKeyPress(phases: [.down, .repeat]) { press in
                        guard press.modifiers.contains(.control) else {
                            return .ignored
                        }
                        switch press.key.character {
                        case "j": moveSelection(by: 1)
                        case "k": moveSelection(by: -1)
                        // ⌃K would otherwise cut to end of line and ⌃J insert
                        // a newline; anything else keeps its usual meaning.
                        default: return .ignored
                        }
                        return .handled
                    }
                ScrollViewReader { list in
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
                    // Six rows show at a time and the catalog returns fifty:
                    // without this the highlight walks off the bottom and the
                    // arrows appear to stop working.
                    .onChange(of: selected?.id) { _, id in
                        guard let id else { return }
                        list.scrollTo(id)
                    }
                    // Back to the top on every keystroke. Driven by the token
                    // rather than by `query`, because the search that rebuilds
                    // the rows and the scroll that follows it have to happen
                    // in that order — two `onChange` on sibling views make no
                    // such promise, and one on the token cannot run before
                    // `runSearch` has set both.
                    .onChange(of: searchGeneration) { _, _ in
                        guard let first = results.first?.id else { return }
                        list.scrollTo(first, anchor: .top)
                    }
                }
                // Was 180, which showed six rows of a catalogue that hands
                // back fifty. It takes what the sheet has now, and the sheet
                // has more.
                .frame(minHeight: 320, maxHeight: .infinity)
                if let searchErrorMessage {
                    Text(searchErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if let selected {
                    gramsRow(
                        kcal100: selected.kcal100, protein100: selected.protein100,
                        carbs100: selected.carbs100, fat100: selected.fat100
                    )
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

    /// Walks the results, reusing the list's own motion rule: from nothing,
    /// down lands on the first row and up on the last, and both ends hold
    /// rather than wrap.
    private func moveSelection(by offset: Int) {
        guard let index = VimMotion.destination(
            from: results.firstIndex { $0.id == selected?.id },
            delta: offset, count: results.count
        ) else { return }
        select(results[index])
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
                fiber100: favorite.fiber100,
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
                        fiber100: product.fiber100,
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
        // Every keystroke starts the list over. Keeping a highlight that
        // happened to survive the new search left it stranded a dozen rows
        // down, out of sight, and Return took a food nobody could see.
        selected = nil
        searchGeneration += 1
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
                fiber100: entry.fiber100,
                productCode: entry.productCode, favoriteGrams: nil
            ))
            if hits.count == 30 { break }
        }
        return hits
    }

    private func subtitle(of hit: FoodSearch.Hit) -> String {
        // Les fibres après les trois macros, et un tiret quand le produit n'en
        // annonce pas — dit plutôt que tu : c'est ce qui permet de choisir,
        // entre deux yaourts équivalents, celui dont la fiche est complète.
        // Une absence muette ne se distinguerait pas d'une colonne qu'on
        // aurait oublié d'afficher.
        let fibres = hit.fiber100.map { "F \(Int($0.rounded()))" } ?? "F —"
        let macros = "\(Int(hit.kcal100.rounded())) kcal · "
            + "P \(Int(hit.protein100.rounded())) · "
            + "G \(Int(hit.carbs100.rounded())) · "
            + "L \(Int(hit.fat100.rounded())) · "
            + "\(fibres) /100 g"
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
                .frame(minHeight: 320, maxHeight: .infinity)
                if let favorite = selectedFavorite {
                    gramsRow(
                        kcal100: favorite.kcal100, protein100: favorite.protein100,
                        carbs100: favorite.carbs100, fat100: favorite.fat100
                    )
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
                DecimalField(placeholder: "kcal", value: $manualKcal)
                Text("Protéines /100 g")
                DecimalField(placeholder: "g", value: $manualProtein)
            }
            GridRow {
                Text("Glucides /100 g")
                DecimalField(placeholder: "g", value: $manualCarbs)
                Text("Lipides /100 g")
                DecimalField(placeholder: "g", value: $manualFat)
            }
            GridRow {
                Text("Quantité")
                DecimalField(placeholder: "g", value: $grams)
                Text(manualPreview)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .gridCellColumns(2)
            }
        }
    }

    private var manualPreview: String {
        portionSummary(
            kcal100: manualKcal, protein100: manualProtein,
            carbs100: manualCarbs, fat100: manualFat
        )
    }

    // MARK: - Shared grams row and add

    private func gramsRow(
        kcal100: Double, protein100: Double, carbs100: Double, fat100: Double
    ) -> some View {
        HStack(spacing: 8) {
            Text("Quantité")
            DecimalField(
                placeholder: "g", value: $grams, width: 80, focus: $gramsFocused
            )
                // ⌃J et ⌃K marchent ici comme dans la recherche, et c'est le
                // champ où l'on en a le plus besoin : un Entrée donné trop
                // vite amène la quantité sur un aliment qu'on n'avait pas
                // choisi, et il fallait jusque-là remonter à la liste pour en
                // changer.
                //
                // Sur le champ et non sur la rangée : c'est là que la
                // recherche pose les siens, et un `onKeyPress` posé sur un
                // ancêtre ne passe qu'après le système de texte d'AppKit, qui
                // lit ⌃K comme « couper jusqu'au bout de la ligne ».
                //
                // Les flèches ne sont pas reprises : dans un champ de nombre,
                // elles appartiennent au point d'insertion.
                .onKeyPress(phases: [.down, .repeat]) { press in
                    guard press.modifiers.contains(.control) else {
                        return .ignored
                    }
                    switch press.key.character {
                    case "j": moveCurrentSelection(by: 1)
                    case "k": moveCurrentSelection(by: -1)
                    default: return .ignored
                    }
                    return .handled
                }
            Text("g")
            Spacer()
            Text(portionSummary(
                kcal100: kcal100, protein100: protein100,
                carbs100: carbs100, fat100: fat100
            ))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Déplace la sélection de la liste qu'on regarde.
    ///
    /// La rangée de quantité est la même sous la recherche et sous les
    /// favoris, mais les deux listes ont chacune la leur ; c'est le mode qui
    /// dit laquelle bouge.
    private func moveCurrentSelection(by offset: Int) {
        switch mode {
        case .search: moveSelection(by: offset)
        case .favorites: moveFavoriteSelection(by: offset)
        case .manual: break
        }
    }

    /// Le même parcours que pour les résultats, sur la liste des favoris :
    /// depuis rien, vers le bas on tombe sur le premier et vers le haut sur le
    /// dernier, et les deux bouts retiennent au lieu de boucler.
    private func moveFavoriteSelection(by offset: Int) {
        guard let index = VimMotion.destination(
            from: favorites.firstIndex { $0.persistentModelID
                == selectedFavorite?.persistentModelID },
            delta: offset, count: favorites.count
        ) else { return }
        let favorite = favorites[index]
        selectedFavorite = favorite
        grams = favorite.grams
    }

    /// What the quantity above amounts to, all four macros.
    ///
    /// The kilocalories alone answered "how much does this cost me", which is
    /// half the question one asks while typing a quantity: the other half is
    /// which of the day's four budgets it spends. Read through `Macros(of:)`,
    /// so the figure previewed here and the figure stored a second later come
    /// from the same arithmetic.
    private func portionSummary(
        kcal100: Double, protein100: Double, carbs100: Double, fat100: Double
    ) -> String {
        let macros = Macros(of: FoodPick(
            foodName: "", kcal100: kcal100, protein100: protein100,
            carbs100: carbs100, fat100: fat100, fiber100: nil, grams: grams
        ))
        return "\(Int(macros.kcal.rounded())) kcal · "
            + "P \(Int(macros.protein.rounded())) · "
            + "G \(Int(macros.carbs.rounded())) · "
            + "L \(Int(macros.fat.rounded()))"
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
                fat100: selected.fat100, fiber100: selected.fiber100,
                grams: grams,
                productCode: selected.productCode
            ))
        case .favorites:
            guard let favorite = selectedFavorite else { return }
            onPick(FoodPick(
                foodName: favorite.foodName, kcal100: favorite.kcal100,
                protein100: favorite.protein100, carbs100: favorite.carbs100,
                fat100: favorite.fat100, fiber100: favorite.fiber100,
                grams: grams,
                productCode: favorite.productCode
            ))
        case .manual:
            onPick(FoodPick(
                foodName: manualName.trimmingCharacters(in: .whitespaces),
                kcal100: manualKcal, protein100: manualProtein,
                carbs100: manualCarbs, fat100: manualFat,
                // Une saisie manuelle ne dit rien des fibres : le formulaire
                // n'en demande pas, et inventer un zéro les compterait comme
                // connues et nulles.
                fiber100: nil, grams: grams,
                productCode: nil
            ))
        }
    }
}
