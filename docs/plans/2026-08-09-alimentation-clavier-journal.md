# Alimentation — Curseur clavier du journal

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre l'écran Alimentation intégralement pilotable au clavier, à parité avec le Jour de suivinut : un curseur sur les repas et les aliments, et toutes les actions (`a e x f K J n c s t ← → ⏎`) relatives à ce curseur ; les sheets s'ouvrent champ focalisé.

**Architecture:** Un `DayCursorModel` pur (positions = en-têtes de repas + lignes, navigation avec compte, clamp) testé sans UI. `NutritionDayView` porte le curseur en `@State`, le rend en surbrillance, et intercepte dans sa fermeture `vimKeys` les commandes qui deviennent contextuelles — avant de déléguer le reste à la fenêtre. Quatre nouveaux `VimCommand` (`K J c s`) ; `e x f n t` sont interceptés côté journal (ils restent des commandes d'activité ailleurs). Les flèches et Entrée passent par des `onKeyPress` dédiés de la vue.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing. Aucune dépendance externe.

**Contexte utilisateur (la demande) :** « avec suivinut je pouvais ajouter/modifier/supprimer très rapidement des aliments […] je peux pas sélectionner une ligne à remonter, un repas pour préciser où ajouter l'aliment quand je fais "a" » — l'objectif est la parité de vitesse au clavier.

## Global Constraints

- macOS 15.0, Swift 6.0 strict. Identifiants/commentaires **anglais**, chaînes visibles **français**.
- Après tout ajout de fichier : `xcodegen generate`. Tests : Swift Testing, noms français.
- Commits : Conventional Commits français, scope `clavier`.
- Bindings cibles (parité suivinut, adaptés aux touches déjà prises par cairn) :
  `j/k` (+compte) curseur, `gg/G` premier/dernier, `a` ajouter au repas du curseur, `e` ou `⏎` éditer la ligne, `x` supprimer la ligne, `f` étoile, `K/J` remonter/descendre la ligne, `n` note du repas du curseur, `c` charger une recette dans le repas du curseur, `s` enregistrer le repas du curseur comme recette, `t` cycler le jour-type (…→ nil → premier), `w` pesée, `←/→` jour ±1, `Échap` aujourd'hui.
- Le curseur se voit (surbrillance système `.quaternary` sur la ligne ou l'en-tête) et se clampe quand le jour ou les données changent.
- Toute interception ne vaut que hors modale (`isPresentingModal`) et ne doit RIEN avaler d'autre : tout le reste continue vers `onCommand`.

---

### Task 1: DayCursorModel + nouvelles commandes

**Files:**
- Create: `Cairn/Features/Nutrition/DayCursorModel.swift`
- Modify: `Cairn/Features/Keyboard/VimCommand.swift`
- Modify: `Cairn/App/RootView.swift` (cases no-op)
- Test: `Tests/DayCursorModelTests.swift`, `Tests/VimKeyBufferTests.swift` (ajouts)

**Interfaces:**
- Produces :

```swift
/// A position in the day's meal list: a meal header, or a food row in it.
struct DayCursor: Equatable {
    var mealIndex: Int
    /// nil = the meal header itself.
    var rowIndex: Int?
}

enum DayCursorModel {
    /// Every reachable position, headers first then their rows, in order.
    static func positions(rowCounts: [Int]) -> [DayCursor]
    /// Moves by `delta` (j/k with count); from nil, a downward move starts at
    /// the first position and an upward one at the last. Clamps at the ends.
    static func move(
        from current: DayCursor?, by delta: Int, rowCounts: [Int]
    ) -> DayCursor?
    /// Re-seats a stale cursor after the data changed (deletion, day switch).
    static func clamp(
        _ cursor: DayCursor?, rowCounts: [Int]
    ) -> DayCursor?
}
```

- `VimCommand` gagne `.moveEntryUp` (`K`), `.moveEntryDown` (`J`), `.loadRecipe` (`c`), `.saveRecipe` (`s`) — tous `actsOnActivities == false`, no-op dans `RootView.perform` (mêmes raisons que `.addFood`).

- [ ] **Step 1: Tests qui échouent**

```swift
// Tests/DayCursorModelTests.swift
import Testing
@testable import Cairn

@Suite("DayCursorModel")
struct DayCursorModelTests {
    @Test("les positions énumèrent en-têtes puis lignes, dans l'ordre")
    func positionsInOrder() {
        let positions = DayCursorModel.positions(rowCounts: [2, 0, 1])
        #expect(positions == [
            DayCursor(mealIndex: 0, rowIndex: nil),
            DayCursor(mealIndex: 0, rowIndex: 0),
            DayCursor(mealIndex: 0, rowIndex: 1),
            DayCursor(mealIndex: 1, rowIndex: nil),
            DayCursor(mealIndex: 2, rowIndex: nil),
            DayCursor(mealIndex: 2, rowIndex: 0),
        ])
    }

    @Test("j descend, k remonte, le compte s'applique, les bords clampent")
    func movesWithCountAndClamps() {
        let counts = [2, 0, 1]
        let start = DayCursorModel.move(from: nil, by: 1, rowCounts: counts)
        #expect(start == DayCursor(mealIndex: 0, rowIndex: nil))
        let down2 = DayCursorModel.move(from: start, by: 2, rowCounts: counts)
        #expect(down2 == DayCursor(mealIndex: 0, rowIndex: 1))
        // Au-delà du bas : clamp sur la dernière position.
        let far = DayCursorModel.move(from: down2, by: 99, rowCounts: counts)
        #expect(far == DayCursor(mealIndex: 2, rowIndex: 0))
        #expect(DayCursorModel.move(from: far, by: -99, rowCounts: counts)
            == DayCursor(mealIndex: 0, rowIndex: nil))
    }

    @Test("depuis rien, k part du bas")
    func upFromNothingStartsAtBottom() {
        #expect(DayCursorModel.move(from: nil, by: -1, rowCounts: [1])
            == DayCursor(mealIndex: 0, rowIndex: 0))
    }

    @Test("le clamp resitue un curseur périmé")
    func clampReseatsStaleCursor() {
        // La ligne 1 du repas 0 a disparu : on retombe sur la plus proche.
        let stale = DayCursor(mealIndex: 0, rowIndex: 1)
        #expect(DayCursorModel.clamp(stale, rowCounts: [1, 0])
            == DayCursor(mealIndex: 0, rowIndex: 0))
        // Le repas 2 n'existe plus.
        #expect(DayCursorModel.clamp(
            DayCursor(mealIndex: 2, rowIndex: nil), rowCounts: [1]
        ) == DayCursor(mealIndex: 0, rowIndex: 0))
        // Rien à montrer : nil.
        #expect(DayCursorModel.clamp(stale, rowCounts: []) == nil)
        #expect(DayCursorModel.clamp(nil, rowCounts: [1]) == nil)
    }
}
```

```swift
    // Tests/VimKeyBufferTests.swift — ajouts dans la suite existante
    @Test("K/J, c et s pilotent le journal")
    func journalRowCommands() {
        #expect(run("K") == [.moveEntryUp])
        #expect(run("J") == [.moveEntryDown])
        #expect(run("c") == [.loadRecipe])
        #expect(run("s") == [.saveRecipe])
        #expect(!VimCommand.moveEntryUp.actsOnActivities)
        #expect(!VimCommand.loadRecipe.actsOnActivities)
    }
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/DayCursorModel.swift
import Foundation

/// A position in the day's meal list: a meal header, or a food row in it.
/// suivinut's day table had exactly these two kinds of rows — the header is
/// selectable so `a`, `n`, `c`, `s` have a target even in an empty meal.
struct DayCursor: Equatable {
    var mealIndex: Int
    var rowIndex: Int?
}

enum DayCursorModel {
    static func positions(rowCounts: [Int]) -> [DayCursor] {
        var positions: [DayCursor] = []
        for (mealIndex, count) in rowCounts.enumerated() {
            positions.append(DayCursor(mealIndex: mealIndex, rowIndex: nil))
            for rowIndex in 0..<count {
                positions.append(
                    DayCursor(mealIndex: mealIndex, rowIndex: rowIndex)
                )
            }
        }
        return positions
    }

    static func move(
        from current: DayCursor?, by delta: Int, rowCounts: [Int]
    ) -> DayCursor? {
        let all = positions(rowCounts: rowCounts)
        guard !all.isEmpty else { return nil }
        guard let current, let index = all.firstIndex(of: current) else {
            // Same rule as the activity list: `j` starts at the top, `k` at
            // the bottom, so both do something on an untouched screen.
            return delta >= 0 ? all.first : all.last
        }
        return all[min(max(index + delta, 0), all.count - 1)]
    }

    static func clamp(
        _ cursor: DayCursor?, rowCounts: [Int]
    ) -> DayCursor? {
        guard let cursor else { return nil }
        let all = positions(rowCounts: rowCounts)
        guard !all.isEmpty else { return nil }
        if all.contains(cursor) { return cursor }
        // The exact spot is gone (deleted row, shorter day): the nearest
        // earlier position keeps the hands where the eyes already are.
        let meal = min(cursor.mealIndex, rowCounts.count - 1)
        if let row = cursor.rowIndex, cursor.mealIndex < rowCounts.count {
            let count = rowCounts[cursor.mealIndex]
            if count > 0 {
                return DayCursor(
                    mealIndex: cursor.mealIndex,
                    rowIndex: min(row, count - 1)
                )
            }
            return DayCursor(mealIndex: cursor.mealIndex, rowIndex: nil)
        }
        let count = rowCounts[meal]
        return DayCursor(mealIndex: meal, rowIndex: count > 0 ? count - 1 : nil)
    }
}
```

`VimCommand.swift` — cases après `.newWeighIn` :

```swift
    /// Move the selected food row inside its meal (suivinut's K/J).
    case moveEntryUp
    case moveEntryDown
    /// Load a recipe into / save a recipe from the cursor's meal.
    case loadRecipe
    case saveRecipe
```

`actsOnActivities` : ajouter les quatre à la branche `false`. Table à une touche de `accept` :

```swift
        case "K": _ = takeCount(); return .moveEntryUp
        case "J": _ = takeCount(); return .moveEntryDown
        case "c": _ = takeCount(); return .loadRecipe
        case "s": _ = takeCount(); return .saveRecipe
```

`RootView.perform` : étendre le case no-op existant :

```swift
        case .addFood, .newWeighIn, .moveEntryUp, .moveEntryDown,
             .loadRecipe, .saveRecipe:
            break
```

- [ ] **Step 4: Vérifier le succès** — `DayCursorModelTests` + `VimKeyBufferTests`, puis suite complète.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/DayCursorModel.swift Cairn/Features/Keyboard/VimCommand.swift Cairn/App/RootView.swift Tests/DayCursorModelTests.swift Tests/VimKeyBufferTests.swift
git commit -m "feat(clavier): curseur pur du journal et commandes K/J/c/s"
```

---

### Task 2: Le curseur dans NutritionDayView

**Files:**
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift`

**Interfaces:**
- Consumes: `DayCursorModel`, les nouveaux `VimCommand`, tout l'existant de la vue (`addTargetSlot`, `editingEntry`, `noteTargetSlot`, `recipeTargetSlot`, `savingRecipeSlot`, `deleteEntry`, `toggleFavorite`, `entry(for:)`, `slotModel(for:)`, `setDayType`, `dayTypes`, `NutritionJournal.move`).
- Produces: l'écran pilotable au clavier. Pas de test unitaire (la logique est dans Task 1) — build + suite complète + vérification visuelle.

- [ ] **Step 1: État et aides**

Dans `NutritionDayView` :

```swift
    @State private var cursor: DayCursor?
```

Aides (le `model` du jour est recalculé dans `journal` — les aides prennent les données en paramètres pour rester appelables depuis la fermeture clavier, qui recalcule à l'identique) :

```swift
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
```

- [ ] **Step 2: Interception clavier**

Remplacer la fermeture `vimKeys` par la version complète (elle garde `.addFood`, `.newWeighIn` et `.clear` existants) :

```swift
        .vimKeys(enabled: !isPresentingModal) { command in
            switch command {
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
```

et les aides d'action :

```swift
    /// K/J: move the row, keep the cursor glued to it.
    private func moveCursorEntry(up: Bool) {
        guard let entry = cursorEntry, let position = cursor,
              let rowIndex = position.rowIndex else { return }
        let counts = currentRowCounts
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
```

- [ ] **Step 3: Flèches, Entrée et clamp**

Sur le `Group` de `body` (après `.vimKeys`) :

```swift
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
```

- [ ] **Step 4: La surbrillance**

`mealSection` reçoit désormais l'index du repas — remplacer la boucle de `journal` :

```swift
                ForEach(
                    Array(model.meals.enumerated()), id: \.element.slotID
                ) { mealIndex, meal in
                    mealSection(meal, mealIndex: mealIndex)
                }
```

Dans `mealSection(_ meal:mealIndex:)` :
- l'en-tête (le `HStack` du nom) gagne :

```swift
            .padding(.horizontal, 6)
            .background(
                cursor == DayCursor(mealIndex: mealIndex, rowIndex: nil)
                    ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 4)
            )
```

- chaque `GridRow` d'aliment (le `ForEach(meal.rows…)` devient `Array(meal.rows.enumerated()), id: \.element.entryID` avec `rowIndex, row`) gagne, après `.font(...)` :

```swift
                        .background(
                            cursor == DayCursor(
                                mealIndex: mealIndex, rowIndex: rowIndex
                            )
                                ? AnyShapeStyle(.quaternary)
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
```

(le modificateur s'applique par cellule comme `.contextMenu` — toute la ligne se teinte.)

- [ ] **Step 5: Builder + suite complète** — build OK, tout vert.

- [ ] **Step 6: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionDayView.swift
git commit -m "feat(clavier): le journal se pilote entièrement au curseur"
```

---

### Task 3: Focus des sheets et documentation

**Files:**
- Modify: `Cairn/Features/Nutrition/FoodPickerView.swift`, `AddFoodSheet.swift` (rien à faire si le focus est dans le picker), `EditEntrySheet.swift`, `WeightEntrySheet.swift`, `MealNoteSheet.swift`, `RecipePickerSheet.swift`
- Modify: `Cairn/Features/Keyboard/KeyboardHelpSheet.swift`, `README.md`, `docs/specs/2026-08-08-alimentation-design.md` (§5, note des raccourcis finaux)

**Interfaces:** inchangées — focus initial + documentation.

- [ ] **Step 1: FoodPickerView — la recherche au clavier de bout en bout**

```swift
    @FocusState private var searchFocused: Bool
    @FocusState private var gramsFocused: Bool
```

- Le `TextField("Rechercher un aliment", …)` gagne :

```swift
                    .focused($searchFocused)
                    .onSubmit {
                        // Return in the search field: take the first hit and
                        // jump to the quantity — type, Return, done. The
                        // suivinut rhythm.
                        if selected == nil { selected = results.first }
                        if selected != nil { gramsFocused = true }
                    }
```

- `gramsRow(kcal100:)` : le `TextField("g", …)` gagne `.focused($gramsFocused)`.
- Sur le `VStack` racine du picker : `.onAppear { catalog = FoodCatalog.openDefault(); searchFocused = true }` (fusionner avec le onAppear existant).
- Quand `mode` change vers `.search`, refocaliser : `.onChange(of: mode) { _, newMode in if newMode == .search { searchFocused = true } }`.

- [ ] **Step 2: Les autres sheets**

- `EditEntrySheet` : `@FocusState private var gramsFocused: Bool` ; `.focused($gramsFocused)` sur le champ grammes ; `.onAppear { gramsFocused = true }` — la quantité est ce qu'on vient corriger.
- `WeightEntrySheet` : idem sur le champ `kg` (`weightFocused`).
- `MealNoteSheet` : idem sur le `TextEditor` (`noteFocused`).
- `RecipePickerSheet` : `@FocusState private var listFocused: Bool` ; `.focused($listFocused)` sur la `List` ; `.onAppear { listFocused = true; if selectedID == nil { selectedID = recipes.first?.persistentModelID } }` — flèches puis ⏎ (le bouton « Appliquer » est déjà `.defaultAction`).

- [ ] **Step 3: Documentation**

`KeyboardHelpSheet` — remplacer le groupe « Journal alimentaire » par :

```swift
        Group(title: "Journal alimentaire", rows: [
            ("j / k", "ligne ou repas suivant / précédent"),
            ("a", "ajouter un aliment au repas sélectionné (pesée sur Poids)"),
            ("e / ⏎", "éditer l'aliment sélectionné"),
            ("x", "supprimer l'aliment sélectionné"),
            ("f", "étoile favori"),
            ("K / J", "remonter / descendre l'aliment"),
            ("n", "note du repas sélectionné"),
            ("c / s", "charger une recette / enregistrer le repas en recette"),
            ("t", "cycler le jour-type"),
            ("w", "nouvelle pesée"),
            ("← / →", "jour précédent / suivant — échap : aujourd'hui"),
        ]),
```

(hauteur du `frame` : 540 → 640.)

`README.md` : remplacer la section « Journal alimentaire » par les mêmes lignes, style des voisines.

`docs/specs/2026-08-08-alimentation-design.md` §5 : ajouter à la fin de la section une note « **Raccourcis finaux du journal** (ajout post-spec, demande utilisateur : parité clavier avec suivinut) : … » listant les bindings ci-dessus.

- [ ] **Step 4: Builder + suite complète** — build OK, tout vert.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/ Cairn/Features/Keyboard/KeyboardHelpSheet.swift README.md docs/specs/2026-08-08-alimentation-design.md
git commit -m "feat(clavier): sheets focalisées à l'ouverture et aide à jour"
```

---

## Après ce plan

Vérification visuelle par l'utilisateur (absent pendant l'exécution) : `j/k` + surbrillance, `a` sur le repas du curseur, séquence complète « a skyr ⏎ 150 ⏎ », `x`/`K`/`J`/`f`/`e`, `t` qui cycle, `c`/`s`, `←/→`, Échap en trois temps (curseur → aujourd'hui → fenêtre). Merge seulement après la revue finale ; si l'utilisateur n'est pas revenu, laisser la branche prête et documentée.
