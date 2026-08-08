# Alimentation — Phase 3 : recettes, favoris, notes, Réglages

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compléter le journal : favoris (étoile + onglet d'ajout rapide), recettes (charger, enregistrer un repas, gérer), notes de repas éditables, et l'onglet Réglages Nutrition (cibles, jours-types, % repas, statut catalogue, import propre).

**Architecture:** Les mutations restent centralisées dans `NutritionJournal` (sémantique portée de `db/journal.py`). Le panneau recherche+manuel de la sheet d'ajout est extrait en `FoodPickerView` réutilisable (ajout au repas ET ajout d'item de recette), qui gagne un segment Favoris. Un onglet « Nutrition » s'ajoute à la `SettingsScene` existante.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing. Aucune dépendance externe.

**Spec :** `docs/specs/2026-08-08-alimentation-design.md` (§5 recettes/favoris/notes, §8 réglages, §11 phase 3). Reliquats des phases 1-2 intégrés : clamp des macros manuelles ≥ 0, titre d'alerte neutre pour le seed, porte d'import « aucun FoodEntry » + contexte SwiftData dédié, garde défensive d'`EditEntrySheet`.

## Global Constraints

- macOS 15.0 minimum, Swift 6.0, `@MainActor` sur tout ce qui touche `ModelContext`.
- Aucune dépendance externe. Identifiants/commentaires **anglais**, chaînes visibles **français**, commentaires « pourquoi ».
- `monospacedDigit` sur les chiffres, couleurs système uniquement.
- Après **tout ajout de fichier source** : `xcodegen generate` avant de builder.
- Tests : Swift Testing, noms en français, jamais XCTest. Commande type :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionJournalTests 2>&1 | tail -5
  ```
- Commits : Conventional Commits en français, scope `alimentation`.
- Sémantique suivinut **à l'identique** : favori identifié par `(food_name, product_code)` (dédoublonné à l'ajout) ; note de repas vide après trim = suppression de la ligne ; `apply_recipe` appende chaque item **en fin de repas** dans l'ordre de la recette ; l'édition d'un favori ne touche que libellé et grammes.

---

### Task 1: NutritionJournal — notes de repas et favoris

**Files:**
- Modify: `Cairn/Features/Nutrition/NutritionJournal.swift`
- Test: `Tests/NutritionJournalTests.swift` (ajouts)

**Interfaces:**
- Consumes: modèles `MealNote`, `FavoriteFood`, `FoodEntry` ; `DateKey`.
- Produces (utilisé par Tasks 3-4-6) :

```swift
struct FavoriteKey: Hashable {
    var foodName: String
    var productCode: String?
}

extension NutritionJournal {
    @MainActor static func setMealNote(
        _ text: String, for dateKey: DateKey, slot: MealSlot,
        in context: ModelContext
    ) throws
    @MainActor static func favoriteKeys(
        in context: ModelContext
    ) throws -> Set<FavoriteKey>
    /// Returns the new state: true = now a favorite.
    @MainActor @discardableResult static func toggleFavorite(
        for entry: FoodEntry, in context: ModelContext
    ) throws -> Bool
    @MainActor static func removeFavorite(
        _ favorite: FavoriteFood, in context: ModelContext
    ) throws
}
```

- [ ] **Step 1: Écrire les tests qui échouent** (à ajouter dans `NutritionJournalTests`)

```swift
    @Test("une note s'upsert, une note vide se supprime")
    func mealNoteUpsertsAndClears() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!

        try NutritionJournal.setMealNote("avant footing", for: key, slot: slot, in: context)
        var notes = try context.fetch(FetchDescriptor<MealNote>())
        #expect(notes.count == 1)
        #expect(notes[0].note == "avant footing")

        try NutritionJournal.setMealNote("  après footing  ", for: key, slot: slot, in: context)
        notes = try context.fetch(FetchDescriptor<MealNote>())
        #expect(notes.count == 1)
        #expect(notes[0].note == "après footing")

        try NutritionJournal.setMealNote("   ", for: key, slot: slot, in: context)
        #expect(try context.fetch(FetchDescriptor<MealNote>()).isEmpty)
    }

    @Test("la bascule favori ajoute puis retire, clé (nom, code)")
    func favoriteToggles() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let entry = try addFood("Skyr", to: slot, context: context)

        #expect(try NutritionJournal.toggleFavorite(for: entry, in: context))
        var favorites = try context.fetch(FetchDescriptor<FavoriteFood>())
        #expect(favorites.count == 1)
        #expect(favorites[0].foodName == "Skyr")
        #expect(favorites[0].grams == 100)
        #expect(try NutritionJournal.favoriteKeys(in: context)
            == [FavoriteKey(foodName: "Skyr", productCode: nil)])

        #expect(try NutritionJournal.toggleFavorite(for: entry, in: context) == false)
        #expect(try context.fetch(FetchDescriptor<FavoriteFood>()).isEmpty)
    }

    @Test("deux favoris de même nom mais code différent coexistent")
    func favoriteKeyIncludesCode() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let generic = try addFood("Riz", to: slot, context: context)
        let branded = try NutritionJournal.addEntry(
            in: context, dateKey: DateKey(raw: "2026-08-08")!, slot: slot,
            foodName: "Riz", kcal100: 350, protein100: 7, carbs100: 77,
            fat100: 1, grams: 120, productCode: "123"
        )

        try NutritionJournal.toggleFavorite(for: generic, in: context)
        try NutritionJournal.toggleFavorite(for: branded, in: context)
        #expect(try context.fetch(FetchDescriptor<FavoriteFood>()).count == 2)

        // Retirer le favori générique laisse le favori de marque en place.
        try NutritionJournal.toggleFavorite(for: generic, in: context)
        let remaining = try context.fetch(FetchDescriptor<FavoriteFood>())
        #expect(remaining.count == 1)
        #expect(remaining[0].productCode == "123")
    }

    @Test("removeFavorite supprime le favori visé")
    func removeFavoriteDeletes() throws {
        let context = try makeContext()
        let favorite = FavoriteFood(
            foodName: "Skyr", kcal100: 57, protein100: 10,
            carbs100: 4, fat100: 0.2, grams: 150
        )
        context.insert(favorite)
        try context.save()
        try NutritionJournal.removeFavorite(favorite, in: context)
        #expect(try context.fetch(FetchDescriptor<FavoriteFood>()).isEmpty)
    }
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionJournalTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter** (à ajouter dans `NutritionJournal.swift`)

```swift
/// Identity of a favorite: name + optional catalog code, exactly suivinut's
/// `(food_name, product_code)` pair — a branded product and a homonymous
/// manual food are two different favorites.
struct FavoriteKey: Hashable {
    var foodName: String
    var productCode: String?
}

extension NutritionJournal {
    /// Trimmed-empty clears the note row entirely — an empty note is not a
    /// note, and suivinut's `set_meal_note` does the same.
    @MainActor
    static func setMealNote(
        _ text: String, for dateKey: DateKey, slot: MealSlot,
        in context: ModelContext
    ) throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = dateKey.raw
        let existing = try context.fetch(
            FetchDescriptor<MealNote>(
                predicate: #Predicate { $0.dateKeyRaw == raw }
            )
        ).first { $0.mealSlot?.persistentModelID == slot.persistentModelID }
        if clean.isEmpty {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.note = clean
        } else {
            context.insert(MealNote(dateKey: dateKey, mealSlot: slot, note: clean))
        }
        try context.save()
    }

    @MainActor
    static func favoriteKeys(in context: ModelContext) throws -> Set<FavoriteKey> {
        Set(try context.fetch(FetchDescriptor<FavoriteFood>()).map {
            FavoriteKey(foodName: $0.foodName, productCode: $0.productCode)
        })
    }

    /// Returns the new state: true = the entry's food is now a favorite. The
    /// favorite copies the entry's per-100 g values and grams — the star
    /// remembers the serving the user actually eats.
    @MainActor @discardableResult
    static func toggleFavorite(
        for entry: FoodEntry, in context: ModelContext
    ) throws -> Bool {
        let matches = try context.fetch(FetchDescriptor<FavoriteFood>())
            .filter {
                $0.foodName == entry.foodName
                    && $0.productCode == entry.productCode
            }
        if matches.isEmpty {
            context.insert(FavoriteFood(
                foodName: entry.foodName, kcal100: entry.kcal100,
                protein100: entry.protein100, carbs100: entry.carbs100,
                fat100: entry.fat100, grams: entry.grams,
                productCode: entry.productCode
            ))
            try context.save()
            return true
        }
        for match in matches { context.delete(match) }
        try context.save()
        return false
    }

    @MainActor
    static func removeFavorite(
        _ favorite: FavoriteFood, in context: ModelContext
    ) throws {
        context.delete(favorite)
        try context.save()
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande (toute la suite `NutritionJournalTests`, 11 tests).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionJournal.swift Tests/NutritionJournalTests.swift
git commit -m "feat(alimentation): notes de repas et favoris dans NutritionJournal"
```

---

### Task 2: NutritionJournal — recettes (+ ordre des items)

**Files:**
- Modify: `Cairn/Model/Recipe.swift` (ajout `sortOrder` sur `RecipeItem`)
- Modify: `Cairn/Features/Nutrition/SuivinutImporter.swift` (l'import numérote les items)
- Modify: `Cairn/Features/Nutrition/NutritionJournal.swift`
- Test: `Tests/NutritionJournalTests.swift` (ajouts), `Tests/SuivinutImporterTests.swift` (assertion d'ordre)

**Interfaces:**
- Consumes: `Recipe`/`RecipeItem`, `NutritionJournal.addEntry` (Task existante).
- Produces (utilisé par Task 5) :

```swift
extension NutritionJournal {
    /// Appends every item of the recipe to the (day, meal), in recipe order.
    @MainActor static func applyRecipe(
        _ recipe: Recipe, to dateKey: DateKey, slot: MealSlot,
        in context: ModelContext
    ) throws
    /// Copies the meal's entries into a new recipe. Throws if the meal is empty.
    @MainActor @discardableResult static func saveMealAsRecipe(
        named name: String, dateKey: DateKey, slot: MealSlot,
        in context: ModelContext
    ) throws -> Recipe
    @MainActor static func deleteRecipe(
        _ recipe: Recipe, in context: ModelContext
    ) throws
    @MainActor @discardableResult static func addRecipeItem(
        to recipe: Recipe, foodName: String, kcal100: Double,
        protein100: Double, carbs100: Double, fat100: Double,
        grams: Double, productCode: String?, in context: ModelContext
    ) throws -> RecipeItem
    @MainActor static func deleteRecipeItem(
        _ item: RecipeItem, in context: ModelContext
    ) throws
}

extension Recipe {
    /// Items in stable display order.
    var orderedItems: [RecipeItem]
}
```

`RecipeItem` gagne `var sortOrder: Int = 0` (migration additive ; suivinut ordonne par id, notre modèle n'avait pas d'ordre — les items importés avant ce champ restent à 0 et se départagent par nom). `orderedItems` trie par `(sortOrder, foodName)`.

- [ ] **Step 1: Écrire les tests qui échouent** (ajouts dans `NutritionJournalTests` ; dans `SuivinutImporterTests.importsEverything`, ajouter un second item de recette à la fixture et vérifier l'ordre)

```swift
    // NutritionJournalTests
    @Test("appliquer une recette appende ses items en fin de repas, dans l'ordre")
    func applyRecipeAppendsInOrder() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!
        _ = try addFood("Déjà là", to: slot, context: context)

        let recipe = Recipe(name: "Porridge", mealSlot: slot)
        context.insert(recipe)
        let oats = RecipeItem(
            foodName: "Flocons", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80
        )
        oats.sortOrder = 0
        oats.recipe = recipe
        let milk = RecipeItem(
            foodName: "Lait", kcal100: 47, protein100: 3.2,
            carbs100: 4.8, fat100: 1.5, grams: 200, productCode: "456"
        )
        milk.sortOrder = 1
        milk.recipe = recipe
        context.insert(oats)
        context.insert(milk)
        try context.save()

        try NutritionJournal.applyRecipe(recipe, to: key, slot: slot, in: context)

        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(entries.map(\.foodName) == ["Déjà là", "Flocons", "Lait"])
        #expect(entries[2].productCode == "456")
        #expect(entries[1].kcal100 == 370)
    }

    @Test("enregistrer un repas comme recette copie ses entrées dans l'ordre")
    func saveMealAsRecipeCopiesEntries() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!
        _ = try addFood("Skyr", to: slot, context: context, dateKey: key)
        _ = try addFood("Granola", to: slot, context: context, dateKey: key)
        // Une entrée d'un autre jour ne doit pas entrer dans la recette.
        _ = try addFood(
            "Hier", to: slot, context: context, dateKey: DateKey(raw: "2026-08-07")!
        )

        let recipe = try NutritionJournal.saveMealAsRecipe(
            named: "Petit-déj type", dateKey: key, slot: slot, in: context
        )
        #expect(recipe.mealSlot?.persistentModelID == slot.persistentModelID)
        #expect(recipe.orderedItems.map(\.foodName) == ["Skyr", "Granola"])
        #expect(recipe.orderedItems[0].grams == 100)
    }

    @Test("enregistrer un repas vide comme recette échoue")
    func saveEmptyMealThrows() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        #expect(throws: (any Error).self) {
            try NutritionJournal.saveMealAsRecipe(
                named: "Vide", dateKey: DateKey(raw: "2026-08-08")!,
                slot: slot, in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
    }

    @Test("ajout et suppression d'items de recette, ordre stable")
    func recipeItemCrud() throws {
        let context = try makeContext()
        let recipe = Recipe(name: "Porridge")
        context.insert(recipe)
        try context.save()

        let first = try NutritionJournal.addRecipeItem(
            to: recipe, foodName: "Flocons", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80, productCode: nil, in: context
        )
        _ = try NutritionJournal.addRecipeItem(
            to: recipe, foodName: "Lait", kcal100: 47, protein100: 3.2,
            carbs100: 4.8, fat100: 1.5, grams: 200, productCode: nil, in: context
        )
        #expect(recipe.orderedItems.map(\.foodName) == ["Flocons", "Lait"])

        try NutritionJournal.deleteRecipeItem(first, in: context)
        #expect(recipe.orderedItems.map(\.foodName) == ["Lait"])

        try NutritionJournal.deleteRecipe(recipe, in: context)
        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecipeItem>()).isEmpty)
    }
```

Dans `SuivinutImporterTests`, fixture : ajouter après l'item existant

```sql
            INSERT INTO recipe_items
                (recipe_id, food_name, product_code, kcal_100g, protein_100g,
                 carbs_100g, fat_100g, grams)
                VALUES (1, 'Lait', NULL, 47, 3.2, 4.8, 1.5, 200);
```

et l'assertion (l'import numérote dans l'ordre de lecture, id croissant) :

```swift
        #expect(recipes[0].orderedItems.map(\.foodName) == ["Flocons", "Lait"])
```

- [ ] **Step 2: Vérifier l'échec**

Run: les deux suites (`NutritionJournalTests`, `SuivinutImporterTests`).
Expected: échec de compilation (`sortOrder`, `orderedItems`, fonctions inconnues).

- [ ] **Step 3: Implémenter**

`Cairn/Model/Recipe.swift` — dans `RecipeItem` :

```swift
    var grams: Double = 0
    /// Display and apply order inside the recipe. suivinut ordered by row id;
    /// items imported before this field exists stay at 0 and fall back to
    /// name order — the best that can be recovered.
    var sortOrder: Int = 0
```

et l'extension (même fichier) :

```swift
extension Recipe {
    var orderedItems: [RecipeItem] {
        (items ?? []).sorted {
            ($0.sortOrder, $0.foodName) < ($1.sortOrder, $1.foodName)
        }
    }
}
```

`SuivinutImporter.swift` — dans la boucle `recipe_items`, numéroter :

```swift
        var recipeItemCounts: [Int64: Int] = [:]
        for row in try db.rows("""
            SELECT recipe_id, food_name, product_code, kcal_100g,
                   protein_100g, carbs_100g, fat_100g, grams
            FROM recipe_items ORDER BY id
            """) {
            ...
            let order = recipeItemCounts[recipeID, default: 0]
            recipeItemCounts[recipeID] = order + 1
            item.sortOrder = order
            ...
        }
```

(`ORDER BY id` reproduit l'ordre suivinut ; le compteur par recette donne 0, 1, 2…)

`NutritionJournal.swift` :

```swift
extension NutritionJournal {
    /// suivinut's `apply_recipe`: each item becomes a journal entry appended
    /// at the end of the meal, macros copied — the journal never references
    /// the recipe afterwards.
    @MainActor
    static func applyRecipe(
        _ recipe: Recipe, to dateKey: DateKey, slot: MealSlot,
        in context: ModelContext
    ) throws {
        for item in recipe.orderedItems {
            try addEntry(
                in: context, dateKey: dateKey, slot: slot,
                foodName: item.foodName, kcal100: item.kcal100,
                protein100: item.protein100, carbs100: item.carbs100,
                fat100: item.fat100, grams: item.grams,
                productCode: item.productCode
            )
        }
    }

    /// The current meal, frozen as a recipe. Refusing an empty meal beats
    /// silently creating a recipe nothing can apply.
    @MainActor @discardableResult
    static func saveMealAsRecipe(
        named name: String, dateKey: DateKey, slot: MealSlot,
        in context: ModelContext
    ) throws -> Recipe {
        let source = try siblings(of: dateKey.raw, slot: slot, in: context)
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !source.isEmpty else {
            throw JournalError(message: "Ce repas est vide — rien à enregistrer.")
        }
        let recipe = Recipe(name: name, mealSlot: slot)
        context.insert(recipe)
        for (index, entry) in source.enumerated() {
            let item = RecipeItem(
                foodName: entry.foodName, kcal100: entry.kcal100,
                protein100: entry.protein100, carbs100: entry.carbs100,
                fat100: entry.fat100, grams: entry.grams,
                productCode: entry.productCode
            )
            item.sortOrder = index
            item.recipe = recipe
            context.insert(item)
        }
        try context.save()
        return recipe
    }

    @MainActor
    static func deleteRecipe(_ recipe: Recipe, in context: ModelContext) throws {
        context.delete(recipe)
        try context.save()
    }

    @MainActor @discardableResult
    static func addRecipeItem(
        to recipe: Recipe, foodName: String, kcal100: Double,
        protein100: Double, carbs100: Double, fat100: Double,
        grams: Double, productCode: String?, in context: ModelContext
    ) throws -> RecipeItem {
        let next = (recipe.orderedItems.map(\.sortOrder).max() ?? -1) + 1
        let item = RecipeItem(
            foodName: foodName, kcal100: kcal100, protein100: protein100,
            carbs100: carbs100, fat100: fat100, grams: grams,
            productCode: productCode
        )
        item.sortOrder = next
        item.recipe = recipe
        context.insert(item)
        try context.save()
        return item
    }

    @MainActor
    static func deleteRecipeItem(
        _ item: RecipeItem, in context: ModelContext
    ) throws {
        context.delete(item)
        try context.save()
    }
}
```

avec, dans le même fichier (`NutritionJournal.swift`), le type d'erreur :

```swift
/// A user-facing journal failure, message in French like every string the
/// alert system shows.
struct JournalError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
```

Note sur le snippet de l'importeur : les `...` marquent les lignes **existantes inchangées** de la boucle `recipe_items` — les seuls changements sont `ORDER BY id` dans le SELECT, la déclaration de `recipeItemCounts` avant la boucle, et les trois lignes de numérotation avant `item.recipe = recipe`.

- [ ] **Step 4: Vérifier le succès**

Run: `NutritionJournalTests` + `SuivinutImporterTests`, puis la suite complète (schéma modifié → tout doit rester vert).
Expected: PASS partout.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Model/Recipe.swift Cairn/Features/Nutrition/SuivinutImporter.swift Cairn/Features/Nutrition/NutritionJournal.swift Tests/NutritionJournalTests.swift Tests/SuivinutImporterTests.swift
git commit -m "feat(alimentation): recettes dans NutritionJournal et ordre des items"
```

---

### Task 3: Étoile favori sur les lignes du jour

**Files:**
- Modify: `Cairn/Features/Nutrition/NutritionDayModel.swift`
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift`
- Modify: `Cairn/Features/Nutrition/EditEntrySheet.swift` (garde défensive, reliquat)
- Test: `Tests/NutritionDayModelTests.swift` (ajouts)

**Interfaces:**
- Consumes: `FavoriteKey`, `NutritionJournal.favoriteKeys/toggleFavorite` (Task 1).
- Produces: `Row` gagne `isFavorite: Bool` ; `compute` gagne le paramètre `favoriteKeys: Set<FavoriteKey>` (les appels existants des tests passent `[]`).

- [ ] **Step 1: Test qui échoue** (ajout dans `NutritionDayModelTests` ; adapter les appels existants de `compute` en ajoutant `favoriteKeys: []`)

```swift
    @Test("une ligne sait si son aliment est en favori")
    func rowsKnowFavoriteState() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!
        let starred = FoodEntry(
            dateKey: key, mealSlot: slot, foodName: "Skyr",
            kcal100: 57, protein100: 10, carbs100: 4, fat100: 0,
            grams: 150, sortOrder: 0
        )
        let plain = FoodEntry(
            dateKey: key, mealSlot: slot, foodName: "Riz",
            kcal100: 350, protein100: 7, carbs100: 77, fat100: 1,
            grams: 120, sortOrder: 1, productCode: "123"
        )
        context.insert(starred)
        context.insert(plain)

        let model = NutritionDayModel.compute(
            entries: [starred, plain], slots: [slot], notes: [],
            dayType: nil, proteinTargetG: 130, fatTargetG: 66,
            favoriteKeys: [FavoriteKey(foodName: "Skyr", productCode: nil)]
        )
        #expect(model.meals[0].rows[0].isFavorite)
        // Même nom ne suffirait pas : la clé inclut le code produit.
        #expect(!model.meals[0].rows[1].isFavorite)
    }
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

`NutritionDayModel.swift` : `Row` gagne `var isFavorite: Bool` ; `compute(entries:slots:notes:dayType:proteinTargetG:fatTargetG:favoriteKeys:)` construit :

```swift
                rows: mealEntries[index].map {
                    Row(
                        entryID: $0.persistentModelID, name: $0.foodName,
                        grams: $0.grams, macros: Macros(of: $0),
                        isFavorite: favoriteKeys.contains(
                            FavoriteKey(
                                foodName: $0.foodName, productCode: $0.productCode
                            )
                        )
                    )
                },
```

(ordonner les champs de `Row` : `entryID`, `name`, `grams`, `macros`, `isFavorite`.)

`NutritionDayView.swift` :
- `journal` calcule `let favorites = (try? NutritionJournal.favoriteKeys(in: modelContext)) ?? []` et le passe à `compute`.
- Chaque `GridRow` d'aliment gagne une **première cellule étoile** (et la ligne d'en-tête une cellule vide `Text("")` en tête pour garder l'alignement) :

```swift
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
                            ...
                        }
```

  (`.yellow` est la couleur système des favoris sur macOS — Finder l'utilise pour les tags par défaut ; pas un hex.)
- Le menu contextuel gagne « Basculer favori » entre « Descendre » et le Divider.
- Aide :

```swift
    private func toggleFavorite(_ id: PersistentIdentifier) {
        guard let entry = entry(for: id) else { return }
        do {
            try NutritionJournal.toggleFavorite(for: entry, in: modelContext)
        } catch {
            writeFailureMessage =
                "Le favori n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }
```

- **Reliquats dans le même passage** :
  - le titre de l'alerte d'import devient neutre : `"Journal alimentaire"` (elle porte aussi les échecs du seed) ;
  - `EditEntrySheet.save()` gagne la garde `guard !entry.isDeleted else { dismiss(); return }` — la sheet retient un modèle vivant et la phase 3 multiplie les chemins de mutation.

- [ ] **Step 4: Vérifier le succès**

Run: `NutritionDayModelTests` puis suite complète (le build valide la vue).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionDayModel.swift Cairn/Features/Nutrition/NutritionDayView.swift Cairn/Features/Nutrition/EditEntrySheet.swift Tests/NutritionDayModelTests.swift
git commit -m "feat(alimentation): étoile favori sur les lignes du journal"
```

---

### Task 4: FoodPickerView — extraction et onglet Favoris

**Files:**
- Create: `Cairn/Features/Nutrition/FoodPickerView.swift`
- Modify: `Cairn/Features/Nutrition/AddFoodSheet.swift` (devient une enveloppe mince)

**Interfaces:**
- Consumes: `FoodCatalog`, `FavoriteFood`, `NutritionJournal.removeFavorite`.
- Produces (utilisé par Task 5 pour l'ajout d'items de recette) :

```swift
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
    // le bouton Annuler reste dans la sheet appelante
}
```

- [ ] **Step 1: Extraire le picker**

Créer `FoodPickerView.swift` en déplaçant depuis `AddFoodSheet` : l'enum `Mode` (qui gagne `case favorites`), tout l'état de recherche/manuel/grammes, `searchPane`, `manualPane`, `gramsRow`, `runSearch`, `subtitle`, `canAdd`, plus `@Environment(\.modelContext)` (le retrait d'un favori écrit) — et le nouveau segment :

```swift
            Picker("", selection: $mode) {
                Text("Recherche").tag(Mode.search)
                Text("Favoris").tag(Mode.favorites)
                Text("Manuel").tag(Mode.manual)
            }
```

Panneau Favoris :

```swift
    @Query(sort: \FavoriteFood.foodName) private var favorites: [FavoriteFood]
    @State private var selectedFavorite: FavoriteFood?

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
```

`canAdd` gagne le cas favoris et le **clamp des macros manuelles** (reliquat) :

```swift
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
```

La confirmation construit le `FoodPick` et appelle `onPick` :

```swift
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
```

Le corps de `FoodPickerView` expose le contenu ET la barre de boutons ? Non — **le picker rend le contenu et un bouton « Ajouter »** ; « Annuler » reste à la sheet appelante. Corps :

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(...)...
            switch mode { ... }
            HStack {
                Spacer()
                Button("Ajouter") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .onAppear { catalog = FoodCatalog.openDefault() }
    }
```

- [ ] **Step 2: Amincir AddFoodSheet**

`AddFoodSheet.swift` devient :

```swift
// Cairn/Features/Nutrition/AddFoodSheet.swift
import SwiftUI
import SwiftData

/// Adding one food to one meal — a thin shell over `FoodPickerView`: the
/// picker chooses the food, this sheet decides it becomes a journal entry.
struct AddFoodSheet: View {
    let slot: MealSlot
    let dateKey: DateKey

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajouter à \(slot.name)")
                .font(.headline)
            FoodPickerView { pick in add(pick) }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 460)
    }

    private func add(_ pick: FoodPick) {
        do {
            try NutritionJournal.addEntry(
                in: modelContext, dateKey: dateKey, slot: slot,
                foodName: pick.foodName, kcal100: pick.kcal100,
                protein100: pick.protein100, carbs100: pick.carbs100,
                fat100: pick.fat100, grams: pick.grams,
                productCode: pick.productCode
            )
            dismiss()
        } catch {
            errorMessage =
                "Votre ajout n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 3: Builder + suite complète**

Run: `xcodegen generate && xcodebuild build … | tail -3` puis `xcodebuild test … -only-testing:CairnTests … | tail -3`.
Expected: build OK, suite verte.

- [ ] **Step 4: Commit**

```bash
git add Cairn/Features/Nutrition/FoodPickerView.swift Cairn/Features/Nutrition/AddFoodSheet.swift
git commit -m "feat(alimentation): sélecteur d'aliment réutilisable avec onglet Favoris"
```

---

### Task 5: Recettes — charger, enregistrer, gérer

**Files:**
- Create: `Cairn/Features/Nutrition/RecipePickerSheet.swift`, `Cairn/Features/Nutrition/RecipesManagerSheet.swift`
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift` (menu d'en-tête de repas + présentations)

**Interfaces:**
- Consumes: `NutritionJournal.applyRecipe/saveMealAsRecipe/deleteRecipe/addRecipeItem/deleteRecipeItem`, `Recipe.orderedItems`, `FoodPickerView`/`FoodPick` (Task 4), `Macros`.
- Produces: `RecipePickerSheet(slot:dateKey:)`, `RecipesManagerSheet()`.

- [ ] **Step 1: RecipePickerSheet**

```swift
// Cairn/Features/Nutrition/RecipePickerSheet.swift
import SwiftUI
import SwiftData

/// Applies one recipe to one meal — the whole recipe lands as entries in a
/// single gesture, then the sheet closes.
struct RecipePickerSheet: View {
    let slot: MealSlot
    let dateKey: DateKey

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var selectedID: PersistentIdentifier?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Charger une recette dans \(slot.name)")
                .font(.headline)
            if recipes.isEmpty {
                ContentUnavailableView(
                    "Aucune recette",
                    systemImage: "book",
                    description: Text(
                        "« Enregistrer ce repas comme recette » en crée une "
                        + "depuis un repas rempli."
                    )
                )
            } else {
                List(recipes, selection: $selectedID) { recipe in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name).lineLimit(1)
                        Text(subtitle(of: recipe))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(recipe.persistentModelID)
                }
                .frame(minHeight: 200)
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
                Button("Appliquer") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 340)
    }

    private func subtitle(of recipe: Recipe) -> String {
        let items = recipe.orderedItems
        let kcal = items.map { Macros(of: $0).kcal }.reduce(0, +)
        let count = items.count
        let plural = count > 1 ? "s" : ""
        var parts = ["\(count) aliment\(plural)", "\(Int(kcal.rounded())) kcal"]
        if let slotName = recipe.mealSlot?.name { parts.append(slotName) }
        return parts.joined(separator: " · ")
    }

    private func apply() {
        guard let recipe = recipes.first(
            where: { $0.persistentModelID == selectedID }
        ) else { return }
        do {
            try NutritionJournal.applyRecipe(
                recipe, to: dateKey, slot: slot, in: modelContext
            )
            dismiss()
        } catch {
            errorMessage =
                "La recette n'a pas pu être appliquée. \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: RecipesManagerSheet**

```swift
// Cairn/Features/Nutrition/RecipesManagerSheet.swift
import SwiftUI
import SwiftData

/// The recipe library: composition, totals, pruning, and adding items via
/// the shared food picker. Creation happens from a filled meal ("Enregistrer
/// ce repas comme recette") — a recipe born empty is a recipe nobody applies.
struct RecipesManagerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var selectedID: PersistentIdentifier?
    @State private var isAddingItem = false
    @State private var errorMessage: String?

    private var selectedRecipe: Recipe? {
        recipes.first { $0.persistentModelID == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recettes")
                .font(.headline)
            HStack(alignment: .top, spacing: 16) {
                List(recipes, selection: $selectedID) { recipe in
                    Text(recipe.name)
                        .lineLimit(1)
                        .tag(recipe.persistentModelID)
                }
                .frame(width: 200)
                Group {
                    if let recipe = selectedRecipe {
                        composition(of: recipe)
                    } else {
                        ContentUnavailableView(
                            "Aucune recette sélectionnée",
                            systemImage: "book"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .sheet(isPresented: $isAddingItem) {
            addItemSheet
        }
    }

    private func composition(of recipe: Recipe) -> some View {
        let items = recipe.orderedItems
        let total = items.map { Macros(of: $0) }.reduce(.zero, +)
        return VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Aliment")
                    Text("g").gridColumnAlignment(.trailing)
                    Text("kcal").gridColumnAlignment(.trailing)
                    Text("").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(items, id: \.persistentModelID) { item in
                    GridRow {
                        Text(item.foodName).lineLimit(1)
                        Text("\(Int(item.grams.rounded()))")
                        Text("\(Int(Macros(of: item).kcal.rounded()))")
                        Button {
                            delete(item)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Retirer de la recette")
                    }
                    .font(.body.monospacedDigit())
                }
            }
            Text(
                "Total : \(Int(total.kcal.rounded())) kcal · "
                + "P \(Int(total.protein.rounded())) · "
                + "G \(Int(total.carbs.rounded())) · "
                + "L \(Int(total.fat.rounded()))"
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack {
                Button("Ajouter un aliment…") { isAddingItem = true }
                Spacer()
                Button("Supprimer la recette", role: .destructive) {
                    delete(recipe)
                }
            }
        }
    }

    private var addItemSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajouter à « \(selectedRecipe?.name ?? "") »")
                .font(.headline)
            FoodPickerView { pick in addItem(pick) }
            HStack {
                Spacer()
                Button("Annuler") { isAddingItem = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 460)
    }

    private func addItem(_ pick: FoodPick) {
        guard let recipe = selectedRecipe else { return }
        do {
            try NutritionJournal.addRecipeItem(
                to: recipe, foodName: pick.foodName, kcal100: pick.kcal100,
                protein100: pick.protein100, carbs100: pick.carbs100,
                fat100: pick.fat100, grams: pick.grams,
                productCode: pick.productCode, in: modelContext
            )
            isAddingItem = false
        } catch {
            errorMessage =
                "L'aliment n'a pas pu être ajouté. \(error.localizedDescription)"
        }
    }

    private func delete(_ item: RecipeItem) {
        do {
            try NutritionJournal.deleteRecipeItem(item, in: modelContext)
        } catch {
            errorMessage =
                "La suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    private func delete(_ recipe: Recipe) {
        selectedID = nil
        do {
            try NutritionJournal.deleteRecipe(recipe, in: modelContext)
        } catch {
            errorMessage =
                "La suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 3: Menu d'en-tête de repas dans NutritionDayView**

États et présentations :

```swift
    @State private var recipeTargetSlot: MealSlot?
    @State private var savingRecipeSlot: MealSlot?
    @State private var recipeName = ""
    @State private var showsRecipesManager = false
```

Dans l'en-tête de `mealSection`, après le bouton `plus.circle` :

```swift
                Menu {
                    Button("Charger une recette…") {
                        recipeTargetSlot = slotModel(for: meal.slotID)
                    }
                    Button("Enregistrer ce repas comme recette…") {
                        recipeName = ""
                        savingRecipeSlot = slotModel(for: meal.slotID)
                    }
                    .disabled(meal.rows.isEmpty)
                    Divider()
                    Button("Gérer les recettes…") { showsRecipesManager = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
```

avec l'aide `private func slotModel(for id: PersistentIdentifier) -> MealSlot? { slots.first { $0.persistentModelID == id } }` (remplacer aussi la fermeture du bouton `plus.circle` pour l'utiliser).

Présentations, à côté des sheets existantes :

```swift
        .sheet(item: $recipeTargetSlot) { slot in
            RecipePickerSheet(slot: slot, dateKey: dateKey)
        }
        .sheet(isPresented: $showsRecipesManager) {
            RecipesManagerSheet()
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
```

et :

```swift
    private func saveRecipe() {
        guard let slot = savingRecipeSlot else { return }
        let name = recipeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try NutritionJournal.saveMealAsRecipe(
                named: name, dateKey: dateKey, slot: slot, in: modelContext
            )
        } catch {
            writeFailureMessage =
                "La recette n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
```

**Important :** `isPresentingModal` (la porte du clavier vim) doit couvrir les nouveaux états : ajouter `|| recipeTargetSlot != nil || savingRecipeSlot != nil || showsRecipesManager`.

- [ ] **Step 4: Builder + suite complète** — build OK, suite verte.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/RecipePickerSheet.swift Cairn/Features/Nutrition/RecipesManagerSheet.swift Cairn/Features/Nutrition/NutritionDayView.swift
git commit -m "feat(alimentation): charger, enregistrer et gérer les recettes"
```

---

### Task 6: Note de repas éditable

**Files:**
- Create: `Cairn/Features/Nutrition/MealNoteSheet.swift`
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift`

**Interfaces:**
- Consumes: `NutritionJournal.setMealNote` (Task 1), `Meal.note`/`slotID`.
- Produces: `MealNoteSheet(slot:dateKey:existingNote:)`.

- [ ] **Step 1: La sheet**

```swift
// Cairn/Features/Nutrition/MealNoteSheet.swift
import SwiftUI
import SwiftData

/// One free-form note per (day, meal). Saving an emptied note deletes it —
/// an empty note is not a note.
struct MealNoteSheet: View {
    let slot: MealSlot
    let dateKey: DateKey
    let existingNote: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?

    init(slot: MealSlot, dateKey: DateKey, existingNote: String?) {
        self.slot = slot
        self.dateKey = dateKey
        self.existingNote = existingNote
        _text = State(initialValue: existingNote ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note — \(slot.name)")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
    }

    private func save() {
        do {
            try NutritionJournal.setMealNote(
                text, for: dateKey, slot: slot, in: modelContext
            )
            dismiss()
        } catch {
            errorMessage =
                "La note n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Brancher**

Dans `NutritionDayView` : état `@State private var noteTargetSlot: MealSlot?` (+ l'ajouter à `isPresentingModal`) ; entrée « Note du repas… » dans le `Menu` d'en-tête (avant le Divider) :

```swift
                    Button("Note du repas…") {
                        noteTargetSlot = slotModel(for: meal.slotID)
                    }
```

présentation (la note existante vient du modèle du jour — retrouver le repas au moment de présenter) :

```swift
        .sheet(item: $noteTargetSlot) { slot in
            MealNoteSheet(
                slot: slot, dateKey: dateKey,
                existingNote: notes.first {
                    $0.dateKeyRaw == dateKey.raw
                        && $0.mealSlot?.persistentModelID == slot.persistentModelID
                }?.note
            )
        }
```

- [ ] **Step 3: Builder + suite complète** — build OK, suite verte.

- [ ] **Step 4: Commit**

```bash
git add Cairn/Features/Nutrition/MealNoteSheet.swift Cairn/Features/Nutrition/NutritionDayView.swift
git commit -m "feat(alimentation): note de repas éditable depuis l'en-tête"
```

---

### Task 7: Logique des Réglages — jours-types, % repas, compte du catalogue

**Files:**
- Modify: `Cairn/Features/Nutrition/NutritionJournal.swift`, `Cairn/Features/Nutrition/FoodCatalog.swift`
- Test: `Tests/NutritionJournalTests.swift`, `Tests/FoodCatalogTests.swift` (ajouts)

**Interfaces:**
- Produces (utilisé par Task 8) :

```swift
extension NutritionJournal {
    @MainActor @discardableResult static func addDayType(
        named name: String, kcalTarget: Int, in context: ModelContext
    ) throws -> DayType
    @MainActor static func deleteDayType(
        _ dayType: DayType, in context: ModelContext
    ) throws
}

extension FoodCatalog {
    func productCount() throws -> Int
}
```

(L'édition inline de nom/kcal/% passe par `@Bindable` + `save()` dans la vue — pas de fonction dédiée pour un simple champ.)

- [ ] **Step 1: Tests qui échouent**

```swift
    // NutritionJournalTests
    @Test("un jour-type s'ajoute en fin d'ordre et se supprime sans casser les jours")
    func dayTypeCrud() throws {
        let context = try makeContext()
        let first = try NutritionJournal.addDayType(
            named: "repos", kcalTarget: 1800, in: context
        )
        let second = try NutritionJournal.addDayType(
            named: "qualité", kcalTarget: 2100, in: context
        )
        #expect(first.sortOrder < second.sortOrder)

        // Un jour qui référence le type supprimé garde sa ligne, type effacé.
        let key = DateKey(raw: "2026-08-08")!
        try NutritionJournal.setDayType(second, for: key, in: context)
        try NutritionJournal.deleteDayType(second, in: context)
        let days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType == nil)
        #expect(try context.fetch(FetchDescriptor<DayType>()).count == 1)
    }
```

```swift
    // FoodCatalogTests
    @Test("productCount compte le catalogue")
    func countsProducts() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.productCount() == 4)
    }
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

```swift
// NutritionJournal.swift
extension NutritionJournal {
    @MainActor @discardableResult
    static func addDayType(
        named name: String, kcalTarget: Int, in context: ModelContext
    ) throws -> DayType {
        let next = (try context.fetch(FetchDescriptor<DayType>())
            .map(\.sortOrder).max() ?? -1) + 1
        let dayType = DayType(name: name, kcalTarget: kcalTarget, sortOrder: next)
        context.insert(dayType)
        try context.save()
        return dayType
    }

    /// Days referencing the deleted type keep their row with a nil type —
    /// SwiftData's default nullify rule, asserted by test so a future
    /// cascade never silently eats journal days.
    @MainActor
    static func deleteDayType(_ dayType: DayType, in context: ModelContext) throws {
        context.delete(dayType)
        try context.save()
    }
}
```

```swift
// FoodCatalog.swift
    func productCount() throws -> Int {
        let rows = try db.rows("SELECT COUNT(*) AS n FROM products")
        return rows.first?["n"]?.intValue ?? 0
    }
```

- [ ] **Step 4: Vérifier le succès** — les deux suites.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionJournal.swift Cairn/Features/Nutrition/FoodCatalog.swift Tests/NutritionJournalTests.swift Tests/FoodCatalogTests.swift
git commit -m "feat(alimentation): logique des réglages (jours-types, compte du catalogue)"
```

---

### Task 8: Onglet Réglages Nutrition

**Files:**
- Create: `Cairn/Features/Nutrition/NutritionSettingsView.swift`
- Modify: `Cairn/Features/Settings/SettingsScene.swift` (nouvel onglet)
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift` (la bannière d'onboarding mentionne les Réglages)

**Interfaces:**
- Consumes: `NutritionJournal.addDayType/deleteDayType`, `FoodCatalog.openDefault/productCount`, `SuivinutImporter`, `NutritionSettings`, `NutritionSeed`.
- Produces: `NutritionSettingsView`, onglet « Nutrition » (`fork.knife`) dans la scène Réglages.

- [ ] **Step 1: La vue**

```swift
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
                    if let importMessage {
                        Text(importMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
```

Note d'implémentation : si, à la vérification visuelle, les `@Query` de la fenêtre principale ne reflètent pas un import fait sur le contexte dédié (rafraîchissement inter-contextes SwiftData), repasser l'import sur `modelContext` (le contexte partagé) et le documenter — la sécurité du rollback est alors portée par la porte « aucun FoodEntry », comme en phase 1.

La **porte spec** est ici la bonne : la section Données n'apparaît que si `entries.isEmpty` (« aucun `FoodEntry` »), pas `slots.isEmpty` — un journal semé mais vide peut donc encore importer, ce que l'onboarding ne permettait pas.

- [ ] **Step 2: L'onglet**

`SettingsScene.swift` :

```swift
            MapSettingsView()
                .tabItem { Label("Cartes", systemImage: "map") }
            NutritionSettingsView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
        }
        .frame(width: 520, height: 460)
```

(La hauteur passe de 380 à 460 : l'onglet Nutrition est le plus dense ; les autres onglets respirent, ils ne débordent pas.)

- [ ] **Step 3: Renvoi depuis l'onboarding**

Dans `NutritionDayView.onboarding`, la description devient :

```swift
                description: Text(
                    "Importez vos données suivinut, ou démarrez un journal "
                    + "vierge. L'import reste possible ensuite dans "
                    + "Réglages → Nutrition tant que le journal est vide."
                )
```

- [ ] **Step 4: Builder + suite complète** — build OK, suite verte.

- [ ] **Step 5: Vérification visuelle**

En mode démo (`STRAVALOCAL_DEMO=1`) : Réglages → Nutrition (cibles éditables, jour-type ajout/suppression, % avec total coloré, statut catalogue) ; étoile favori sur une ligne ; onglet Favoris de la sheet d'ajout (grammes préremplis) ; enregistrer un repas comme recette puis la recharger ; note de repas (créer, modifier, vider = supprimer) ; gestionnaire de recettes (ajouter/retirer un item, supprimer).

- [ ] **Step 6: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionSettingsView.swift Cairn/Features/Settings/SettingsScene.swift Cairn/Features/Nutrition/NutritionDayView.swift
git commit -m "feat(alimentation): onglet Réglages Nutrition"
```

---

## Après cette phase

Omission délibérée de cette phase, à consigner : le **réordonnancement** des jours-types (spec §8) — leur `sortOrder` n'a d'effet visible nulle part (le menu du jour trie par kcal) ; à revoir en phase 6 ou à retirer de la spec.

Phase 4 (plan séparé) : l'écran Poids — `WeightStats` (régression, Δ 7 j, estimation), graphe Swift Charts avec objectif et minimum, liste des pesées, entrée sidebar « Poids » (`gp` en phase 6). Phase 5 : pipeline catalogue (téléchargement CSV avec reprise, reconstruction, progression dans cet onglet Réglages — remplacer alors le texte de statut par le bouton de mise à jour). Phase 6 : clavier (`gn`/`gp`, raccourcis d'écran), drag de réordonnancement (spec §5), message d'erreur de recherche (spec §9), volet détail activité résiduel.
