# Alimentation — Phase 1 : modèles, import suivinut, journal en lecture

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poser les fondations de la section Alimentation : modèles SwiftData, import unique de `journal.db` (suivinut), calculs nutritionnels purs, et un écran journal en lecture seule accessible depuis la sidebar.

**Architecture:** Les données de nutrition entrent dans le store SwiftData existant (nouveaux `@Model` ajoutés au schéma). Un wrapper minimal sur libsqlite3 système lit le `journal.db` suivinut pour un import transactionnel unique. La vue suit le motif Statistiques : calcul pur (`NutritionDayModel.compute`) appelé depuis `body`, vue sans ViewModel.

**Tech Stack:** Swift 6 strict, SwiftUI, SwiftData, SQLite3 système (`import SQLite3`), Swift Testing. Aucune dépendance externe.

**Spec :** `docs/specs/2026-08-08-alimentation-design.md` (phases 2–6 dans des plans ultérieurs ; le mini-calendrier et le panneau stats de la colonne détail viendront avec les phases 4 et 6).

## Global Constraints

- macOS 15.0 minimum, Swift 6.0, concurrence stricte (`@MainActor` sur tout ce qui touche un `ModelContext`).
- Aucun gestionnaire de paquets, aucune dépendance externe — libsqlite3 est une bibliothèque système.
- Identifiants, types et commentaires en **anglais** ; chaînes visibles par l'utilisateur en **français** ; commentaires « pourquoi », jamais « quoi ».
- Chiffres affichés en `monospacedDigit()`, couleurs système uniquement (pas de hex).
- Après **tout ajout de fichier source** : `xcodegen generate` avant de builder.
- Tests : Swift Testing (`import Testing`, `@Suite`, `#expect`), noms de tests en français, jamais XCTest.
- Commits : Conventional Commits en français, scope `alimentation`, sujet en phrase descriptive.
- Commande de test (remplacer la cible `-only-testing` par la suite visée) :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/DateKeyTests 2>&1 | tail -5
  ```

---

### Task 1: DateKey — identité de jour calendaire

**Files:**
- Create: `Cairn/Model/DateKey.swift`
- Test: `Tests/DateKeyTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `struct DateKey: Hashable, Comparable, Sendable` — `init(_ date: Date, calendar: Calendar = .current)`, `init?(raw: String)`, `var raw: String`, `func date(calendar: Calendar = .current) -> Date`, `func advanced(by days: Int, calendar: Calendar = .current) -> DateKey`. Toutes les tâches suivantes stockent `dateKeyRaw: String` et convertissent via ce type.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/DateKeyTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("DateKey")
struct DateKeyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    @Test("une Date se projette sur le jour calendaire local")
    func fromDate() {
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 8, hour: 23, minute: 30)
        )!
        #expect(DateKey(date, calendar: calendar).raw == "2026-08-08")
    }

    @Test("les chaînes invalides sont refusées", arguments: [
        "abc", "2026-13-01", "2026-08-32", "20260808", "2026-8-8", ""
    ])
    func rejectsInvalidRaw(raw: String) {
        #expect(DateKey(raw: raw) == nil)
    }

    @Test("une chaîne valide fait l'aller-retour")
    func roundTripsRaw() {
        let key = DateKey(raw: "2026-08-08")
        #expect(key?.raw == "2026-08-08")
    }

    @Test("l'ordre lexicographique est l'ordre chronologique")
    func ordersChronologically() {
        #expect(DateKey(raw: "2026-08-08")! < DateKey(raw: "2026-08-09")!)
        #expect(DateKey(raw: "2025-12-31")! < DateKey(raw: "2026-01-01")!)
    }

    @Test("advanced(by:) franchit les frontières de mois")
    func advancesAcrossMonths() {
        let key = DateKey(raw: "2026-08-31")!
        #expect(key.advanced(by: 1, calendar: calendar).raw == "2026-09-01")
        #expect(key.advanced(by: -31, calendar: calendar).raw == "2026-07-31")
    }

    @Test("date() rend minuit local du bon jour")
    func dateIsLocalMidnight() {
        let key = DateKey(raw: "2026-08-08")!
        let date = key.date(calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts.year == 2026 && parts.month == 8 && parts.day == 8)
        #expect(parts.hour == 0)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/DateKeyTests 2>&1 | tail -5`
Expected: échec de compilation, `DateKey` inconnu. (Créer d'abord un `Cairn/Model/DateKey.swift` vide pour que xcodegen liste le fichier, ou créer le fichier au step 3 et accepter que ce step échoue à la compilation — les deux prouvent que le test ne passe pas sans l'implémentation.)

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Model/DateKey.swift
import Foundation

/// A calendar day identity — "2026-08-08" — the unit the food journal is
/// keyed on. A validated string rather than a `Date`: a meal belongs to a
/// local calendar day, and normalising instants across DST switches is
/// exactly the bug class this avoids. suivinut stored TEXT dates for the
/// same reason, which also makes the import a straight copy.
struct DateKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    let raw: String

    init?(raw: String) {
        guard Self.components(of: raw) != nil else { return nil }
        self.raw = raw
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        raw = String(
            format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!
        )
    }

    /// Local midnight, for calendars and charts that need a real `Date`.
    func date(calendar: Calendar = .current) -> Date {
        let (year, month, day) = Self.components(of: raw)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    func advanced(by days: Int, calendar: Calendar = .current) -> DateKey {
        let moved = calendar.date(
            byAdding: .day, value: days, to: date(calendar: calendar)
        )!
        return DateKey(moved, calendar: calendar)
    }

    /// ISO ordering: lexicographic on the raw string *is* chronological,
    /// which is why the format is validated so strictly at init.
    static func < (lhs: DateKey, rhs: DateKey) -> Bool { lhs.raw < rhs.raw }

    var description: String { raw }

    private static func components(of raw: String) -> (Int, Int, Int)? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS, toutes les assertions vertes.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Model/DateKey.swift Tests/DateKeyTests.swift
git commit -m "feat(alimentation): identité de jour calendaire DateKey"
```

---

### Task 2: Modèles SwiftData du journal nutritionnel

**Files:**
- Create: `Cairn/Model/DayType.swift`, `Cairn/Model/MealSlot.swift`, `Cairn/Model/NutritionDay.swift`, `Cairn/Model/FoodEntry.swift`, `Cairn/Model/MealNote.swift`, `Cairn/Model/Recipe.swift`, `Cairn/Model/FavoriteFood.swift`, `Cairn/Model/WeightEntry.swift`
- Modify: `Cairn/Model/ModelContainer+App.swift:5-9` (liste `schema`)
- Test: `Tests/NutritionModelsTests.swift`

**Interfaces:**
- Consumes: `DateKey` (Task 1) — les modèles stockent `dateKeyRaw: String` + propriété calculée `dateKey`.
- Produces: les 9 `@Model` ci-dessous, avec exactement ces noms de propriétés — l'importeur (Task 5), le modèle d'affichage (Task 6), le semis (Task 7) et la vue (Task 8) les utilisent tels quels.

Convention du dépôt respectée : valeurs par défaut sur toutes les propriétés persistées, `rawValue` persisté + propriété calculée typée par-dessus (`dateKeyRaw`/`dateKey`, comme `sportTypeRaw`/`sportType`).

- [ ] **Step 1: Écrire le test de persistance qui échoue**

```swift
// Tests/NutritionModelsTests.swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Modèles nutrition")
@MainActor
struct NutritionModelsTests {
    @Test("une journée complète survit à un aller-retour en base")
    func persistsAFullDay() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let dayType = DayType(name: "sortie longue", kcalTarget: 2500, sortOrder: 3)
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let day = NutritionDay(dateKey: DateKey(raw: "2026-08-08")!, dayType: dayType)
        let entry = FoodEntry(
            dateKey: DateKey(raw: "2026-08-08")!, mealSlot: slot,
            foodName: "Flocons d'avoine", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80, sortOrder: 0
        )
        let note = MealNote(
            dateKey: DateKey(raw: "2026-08-08")!, mealSlot: slot, note: "avant footing"
        )
        let weight = WeightEntry(dateKey: DateKey(raw: "2026-08-08")!, weightKg: 71.2)
        context.insert(dayType)
        context.insert(slot)
        context.insert(day)
        context.insert(entry)
        context.insert(note)
        context.insert(weight)
        try context.save()

        let fetchedDays = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(fetchedDays.count == 1)
        #expect(fetchedDays[0].dayType?.name == "sortie longue")
        #expect(fetchedDays[0].dateKey?.raw == "2026-08-08")
        let fetchedEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(fetchedEntries.count == 1)
        #expect(fetchedEntries[0].mealSlot?.name == "Petit-déj")
        #expect(fetchedEntries[0].kcal100 == 370)
        let fetchedNotes = try context.fetch(FetchDescriptor<MealNote>())
        #expect(fetchedNotes[0].note == "avant footing")
        let fetchedWeights = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(fetchedWeights[0].weightKg == 71.2)
    }

    @Test("une recette et ses items se suppriment en cascade")
    func recipeCascadesToItems() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let recipe = Recipe(name: "Porridge")
        let item = RecipeItem(
            foodName: "Flocons", kcal100: 370, protein100: 13,
            carbs100: 60, fat100: 7, grams: 80
        )
        item.recipe = recipe
        context.insert(recipe)
        context.insert(item)
        try context.save()

        context.delete(recipe)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<RecipeItem>()).isEmpty)
    }

    @Test("un favori persiste ses macros dénormalisées")
    func persistsFavorite() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let favorite = FavoriteFood(
            foodName: "Skyr", kcal100: 57, protein100: 10,
            carbs100: 4, fat100: 0.2, grams: 150
        )
        context.insert(favorite)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<FavoriteFood>())
        #expect(fetched[0].protein100 == 10)
        #expect(fetched[0].grams == 150)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionModelsTests 2>&1 | tail -5`
Expected: échec de compilation (types inconnus).

- [ ] **Step 3: Implémenter les modèles**

```swift
// Cairn/Model/DayType.swift
import Foundation
import SwiftData

/// A named calorie target — "repos", "sortie longue" — assigned to a day.
/// The athlete's need varies with training, so the target belongs to a
/// reusable day *type* rather than to each date.
@Model
final class DayType {
    var name: String = ""
    var kcalTarget: Int = 0
    var sortOrder: Int = 0

    init(name: String, kcalTarget: Int, sortOrder: Int = 0) {
        self.name = name
        self.kcalTarget = kcalTarget
        self.sortOrder = sortOrder
    }
}
```

```swift
// Cairn/Model/MealSlot.swift
import Foundation
import SwiftData

/// A meal of the day — "Petit-déj", "Dîner" — with its share of the daily
/// calorie plan in percent. 0 % is a valid slot (a snack that borrows from
/// the day rather than owning a share).
@Model
final class MealSlot {
    var name: String = ""
    var sortOrder: Int = 0
    var targetPct: Int = 0

    init(name: String, sortOrder: Int = 0, targetPct: Int = 0) {
        self.name = name
        self.sortOrder = sortOrder
        self.targetPct = targetPct
    }
}
```

```swift
// Cairn/Model/NutritionDay.swift
import Foundation
import SwiftData

/// One journal day's metadata — today just which day type applies. Entries
/// are keyed by date string, not by this object: a day with meals but no
/// chosen type simply has no `NutritionDay` row, exactly like suivinut.
@Model
final class NutritionDay {
    #Unique<NutritionDay>([\.dateKeyRaw])

    var dateKeyRaw: String = ""
    var dayType: DayType?

    init(dateKey: DateKey, dayType: DayType? = nil) {
        self.dateKeyRaw = dateKey.raw
        self.dayType = dayType
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
```

```swift
// Cairn/Model/FoodEntry.swift
import Foundation
import SwiftData

/// One food eaten at one meal. The per-100 g values are copied here at entry
/// time — denormalised on purpose, so history stays true even if the OFF
/// catalog is rebuilt or deleted. `productCode` is only a reference back.
@Model
final class FoodEntry {
    #Index<FoodEntry>([\.dateKeyRaw])

    var dateKeyRaw: String = ""
    var mealSlot: MealSlot?
    var productCode: String?
    var foodName: String = ""
    var kcal100: Double = 0
    var protein100: Double = 0
    var carbs100: Double = 0
    var fat100: Double = 0
    var grams: Double = 0
    var sortOrder: Int = 0

    init(
        dateKey: DateKey, mealSlot: MealSlot?, foodName: String,
        kcal100: Double, protein100: Double, carbs100: Double,
        fat100: Double, grams: Double, sortOrder: Int = 0,
        productCode: String? = nil
    ) {
        self.dateKeyRaw = dateKey.raw
        self.mealSlot = mealSlot
        self.foodName = foodName
        self.kcal100 = kcal100
        self.protein100 = protein100
        self.carbs100 = carbs100
        self.fat100 = fat100
        self.grams = grams
        self.sortOrder = sortOrder
        self.productCode = productCode
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
```

```swift
// Cairn/Model/MealNote.swift
import Foundation
import SwiftData

/// A free-form note on one (day, meal) pair. Uniqueness is enforced by the
/// fetch-or-create call sites rather than a compound constraint — SwiftData
/// unique constraints on relationships are not worth the migration risk.
@Model
final class MealNote {
    var dateKeyRaw: String = ""
    var mealSlot: MealSlot?
    var note: String = ""

    init(dateKey: DateKey, mealSlot: MealSlot?, note: String) {
        self.dateKeyRaw = dateKey.raw
        self.mealSlot = mealSlot
        self.note = note
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
```

```swift
// Cairn/Model/Recipe.swift
import Foundation
import SwiftData

/// A reusable set of foods applied to a meal in one gesture.
@Model
final class Recipe {
    var name: String = ""
    var mealSlot: MealSlot?
    @Relationship(deleteRule: .cascade, inverse: \RecipeItem.recipe)
    var items: [RecipeItem]? = []

    init(name: String, mealSlot: MealSlot? = nil) {
        self.name = name
        self.mealSlot = mealSlot
    }
}

/// One ingredient of a recipe, macros denormalised like `FoodEntry`.
@Model
final class RecipeItem {
    var recipe: Recipe?
    var foodName: String = ""
    var productCode: String?
    var kcal100: Double = 0
    var protein100: Double = 0
    var carbs100: Double = 0
    var fat100: Double = 0
    var grams: Double = 0

    init(
        foodName: String, kcal100: Double, protein100: Double,
        carbs100: Double, fat100: Double, grams: Double,
        productCode: String? = nil
    ) {
        self.foodName = foodName
        self.kcal100 = kcal100
        self.protein100 = protein100
        self.carbs100 = carbs100
        self.fat100 = fat100
        self.grams = grams
        self.productCode = productCode
    }
}
```

```swift
// Cairn/Model/FavoriteFood.swift
import Foundation
import SwiftData

/// A recurring food kept one click away, with its usual serving in grams.
@Model
final class FavoriteFood {
    var foodName: String = ""
    var productCode: String?
    var kcal100: Double = 0
    var protein100: Double = 0
    var carbs100: Double = 0
    var fat100: Double = 0
    var grams: Double = 0

    init(
        foodName: String, kcal100: Double, protein100: Double,
        carbs100: Double, fat100: Double, grams: Double,
        productCode: String? = nil
    ) {
        self.foodName = foodName
        self.kcal100 = kcal100
        self.protein100 = protein100
        self.carbs100 = carbs100
        self.fat100 = fat100
        self.grams = grams
        self.productCode = productCode
    }
}
```

```swift
// Cairn/Model/WeightEntry.swift
import Foundation
import SwiftData

/// One weigh-in per day at most — entering a day twice replaces it, which
/// the unique key enforces at the store level.
@Model
final class WeightEntry {
    #Unique<WeightEntry>([\.dateKeyRaw])

    var dateKeyRaw: String = ""
    var weightKg: Double = 0
    var note: String?

    init(dateKey: DateKey, weightKg: Double, note: String? = nil) {
        self.dateKeyRaw = dateKey.raw
        self.weightKg = weightKg
        self.note = note
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
```

Puis enregistrer les modèles dans le schéma — `Cairn/Model/ModelContainer+App.swift` :

```swift
    static let schema = Schema([
        Activity.self, ActivityStreams.self, Athlete.self,
        Lap.self, Gear.self, SyncState.self, DiscardedActivity.self,
        ActivityPhoto.self,
        // Nutrition — added as a block: SwiftData treats new models as a
        // lightweight migration, existing activity data is untouched.
        DayType.self, MealSlot.self, NutritionDay.self, FoodEntry.self,
        MealNote.self, Recipe.self, RecipeItem.self, FavoriteFood.self,
        WeightEntry.self,
    ])
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2, puis la suite complète (`-only-testing:CairnTests`) pour vérifier qu'aucun test existant ne casse avec le schéma étendu.
Expected: PASS partout.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Model/ Tests/NutritionModelsTests.swift
git commit -m "feat(alimentation): modèles SwiftData du journal nutritionnel"
```

---

### Task 3: NutritionMath — calculs purs et cibles adaptatives

**Files:**
- Create: `Cairn/Features/Nutrition/NutritionMath.swift`
- Test: `Tests/NutritionMathTests.swift`

**Interfaces:**
- Consumes: `FoodEntry`, `RecipeItem`, `FavoriteFood` (Task 2) — conformés à `FoodPortion` ici.
- Produces:
  - `protocol FoodPortion` (`kcal100`, `protein100`, `carbs100`, `fat100`, `grams`, tous `Double { get }`)
  - `struct Macros: Equatable, Sendable` — `kcal`, `protein`, `carbs`, `fat: Double` ; `static let zero` ; `+` ; `func scaled(_ factor: Double) -> Macros` ; `init(of portion: some FoodPortion)`
  - `enum NutritionMath` — `dailyTargets(kcalTarget: Int?, proteinG: Double, fatG: Double) -> Macros?` ; `mealTarget(daily: Macros, pct: Int) -> Macros` ; `remainingDay(daily: Macros, consumed: Macros) -> Macros` ; `struct MealState { var pct: Int; var started: Bool; var consumed: Macros }` ; `adaptiveMealTargets(daily: Macros?, meals: [MealState]) -> [Macros?]`

C'est le portage fidèle de `suivinut/domain/nutrition.py` — l'algorithme adaptatif est commenté dans le code source Python, reproduire la même sémantique.

- [ ] **Step 1: Écrire les tests qui échouent** (cas portés de `tests/test_nutrition.py`)

```swift
// Tests/NutritionMathTests.swift
import Testing
import Foundation
@testable import Cairn

private struct TestPortion: FoodPortion {
    var kcal100: Double = 100
    var protein100: Double = 10
    var carbs100: Double = 20
    var fat100: Double = 5
    var grams: Double
}

@Suite("NutritionMath")
struct NutritionMathTests {
    @Test("les macros d'une portion suivent les grammes")
    func portionMacrosScaleByGrams() {
        let macros = Macros(of: TestPortion(grams: 250))
        #expect(macros == Macros(kcal: 250, protein: 25, carbs: 50, fat: 12.5))
    }

    @Test("addition et échelle")
    func addAndScale() {
        let sum = Macros(kcal: 100, protein: 10, carbs: 20, fat: 5)
            + Macros(kcal: 50, protein: 5, carbs: 10, fat: 2)
        #expect(sum == Macros(kcal: 150, protein: 15, carbs: 30, fat: 7))
        #expect(
            Macros(kcal: 100, protein: 10, carbs: 20, fat: 5).scaled(0.5)
                == Macros(kcal: 50, protein: 5, carbs: 10, fat: 2.5)
        )
    }

    @Test("la cible du jour déduit les glucides")
    func dailyTargetsDeriveCarbs() throws {
        // 2100 kcal, 145 P, 66 L -> glucides = (2100 - 580 - 594) / 4 = 231.5
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2100, proteinG: 145, fatG: 66)
        )
        #expect(daily.kcal == 2100)
        #expect(daily.protein == 145)
        #expect(daily.fat == 66)
        #expect(abs(daily.carbs - 231.5) < 0.001)
    }

    @Test("pas de cible kcal, pas de cible du jour")
    func dailyTargetsNilWithoutKcal() {
        #expect(NutritionMath.dailyTargets(kcalTarget: nil, proteinG: 145, fatG: 66) == nil)
    }

    @Test("les glucides déduits ne deviennent jamais négatifs")
    func carbsClampAtZero() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 500, proteinG: 145, fatG: 66)
        )
        #expect(daily.carbs == 0)
    }

    @Test("le budget restant borne chaque macro à zéro")
    func remainingDayClampsEachMacro() {
        let remaining = NutritionMath.remainingDay(
            daily: Macros(kcal: 2000, protein: 100, carbs: 250, fat: 60),
            consumed: Macros(kcal: 1800, protein: 120, carbs: 100, fat: 55)
        )
        #expect(remaining.kcal == 200)
        #expect(remaining.protein == 0)
        #expect(remaining.carbs == 150)
        #expect(remaining.fat == 5)
    }

    @Test("le dernier repas entamé affiche le reste réel du jour")
    func lastStartedMealShowsTrueRemaining() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2500, proteinG: 149, fatG: 66)
        )
        let meals: [NutritionMath.MealState] = [
            .init(pct: 28, started: true,
                  consumed: Macros(kcal: 365, protein: 25, carbs: 63, fat: 4)),
            .init(pct: 33, started: true,
                  consumed: Macros(kcal: 760, protein: 52, carbs: 89, fat: 22)),
            .init(pct: 0, started: true,
                  consumed: Macros(kcal: 742, protein: 5, carbs: 134, fat: 21)),
            .init(pct: 39, started: true,
                  consumed: Macros(kcal: 568, protein: 32, carbs: 56, fat: 20)),
        ]
        let targets = NutritionMath.adaptiveMealTargets(daily: daily, meals: meals)
        // Terminés -> part fixe du plan.
        #expect(targets[0] == NutritionMath.mealTarget(daily: daily, pct: 28))
        #expect(targets[1] == NutritionMath.mealTarget(daily: daily, pct: 33))
        // 0 % -> pas de cible.
        #expect(targets[2] == nil)
        // Dîner en cours : jour − (365+760+742) = 633, PAS 39 % de 2500.
        let dinner = try #require(targets[3])
        #expect(abs(dinner.kcal - 633) < 0.001)
        #expect(abs(dinner.carbs - (327.5 - 286)) < 0.001)
    }

    @Test("la cible du repas en cours ne saute pas quand on l'entame")
    func noFlipWhenCurrentMealStarts() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2500, proteinG: 149, fatG: 66)
        )
        let done: [NutritionMath.MealState] = [
            .init(pct: 28, started: true,
                  consumed: Macros(kcal: 365, protein: 25, carbs: 63, fat: 4)),
            .init(pct: 33, started: true,
                  consumed: Macros(kcal: 760, protein: 52, carbs: 89, fat: 22)),
            .init(pct: 0, started: true,
                  consumed: Macros(kcal: 742, protein: 5, carbs: 134, fat: 21)),
        ]
        let empty = NutritionMath.adaptiveMealTargets(
            daily: daily, meals: done + [.init(pct: 39, started: false, consumed: .zero)]
        )
        let started = NutritionMath.adaptiveMealTargets(
            daily: daily,
            meals: done + [.init(
                pct: 39, started: true,
                consumed: Macros(kcal: 568, protein: 32, carbs: 56, fat: 20)
            )]
        )
        let before = try #require(empty[3])
        let after = try #require(started[3])
        #expect(abs(before.kcal - after.kcal) < 0.001)
        #expect(abs(before.carbs - after.carbs) < 0.001)
    }

    @Test("un repas terminé grève le budget, les repas à venir se partagent le reste réel")
    func finishedMealReducesBudget() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2000, proteinG: 100, fatG: 60)
        )
        let meals: [NutritionMath.MealState] = [
            .init(pct: 20, started: true,
                  consumed: Macros(kcal: 400, protein: 20, carbs: 40, fat: 8)),
            .init(pct: 30, started: true,
                  consumed: Macros(kcal: 300, protein: 15, carbs: 30, fat: 6)),
            .init(pct: 25, started: false, consumed: .zero),
            .init(pct: 25, started: false, consumed: .zero),
        ]
        let targets = NutritionMath.adaptiveMealTargets(daily: daily, meals: meals)
        #expect(targets[0] == NutritionMath.mealTarget(daily: daily, pct: 20))
        // B en cours : part du budget en jeu (2000 − 400) × 30/80.
        #expect(abs(try #require(targets[1]).kcal - 1600 * 30 / 80) < 0.001)
        // C et D : reste réel (2000 − 400 − 300) réparti 25/50.
        #expect(abs(try #require(targets[2]).kcal - 1300 * 25 / 50) < 0.001)
        #expect(abs(try #require(targets[3]).kcal - 1300 * 25 / 50) < 0.001)
    }

    @Test("budget explosé : la cible en cours tombe à zéro, jamais négative")
    func blownBudgetClampsToZero() throws {
        let daily = try #require(
            NutritionMath.dailyTargets(kcalTarget: 2000, proteinG: 100, fatG: 60)
        )
        let meals: [NutritionMath.MealState] = [
            .init(pct: 50, started: true,
                  consumed: Macros(kcal: 2200, protein: 120, carbs: 300, fat: 70)),
            .init(pct: 50, started: true,
                  consumed: Macros(kcal: 100, protein: 5, carbs: 20, fat: 3)),
        ]
        let targets = NutritionMath.adaptiveMealTargets(daily: daily, meals: meals)
        let current = try #require(targets[1])
        #expect(current.kcal == 0)
        #expect(current.carbs == 0)
    }

    @Test("sans cible du jour, aucune cible de repas")
    func noDailyMeansAllNil() {
        let targets = NutritionMath.adaptiveMealTargets(
            daily: nil,
            meals: [
                .init(pct: 28, started: true,
                      consumed: Macros(kcal: 100, protein: 1, carbs: 1, fat: 1)),
                .init(pct: 39, started: false, consumed: .zero),
            ]
        )
        #expect(targets == [nil, nil])
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionMathTests 2>&1 | tail -5`
Expected: échec de compilation (types inconnus).

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/NutritionMath.swift
import Foundation

/// Anything carrying per-100 g values and a weight: a journal entry, a
/// recipe item, a favorite. One protocol so the macro arithmetic is written
/// once — suivinut's `entry_macros` accepted the same duck-typed shape.
protocol FoodPortion {
    var kcal100: Double { get }
    var protein100: Double { get }
    var carbs100: Double { get }
    var fat100: Double { get }
    var grams: Double { get }
}

extension FoodEntry: FoodPortion {}
extension RecipeItem: FoodPortion {}
extension FavoriteFood: FoodPortion {}

struct Macros: Equatable, Sendable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    init(of portion: some FoodPortion) {
        let factor = portion.grams / 100
        self.init(
            kcal: portion.kcal100 * factor,
            protein: portion.protein100 * factor,
            carbs: portion.carbs100 * factor,
            fat: portion.fat100 * factor
        )
    }

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat
        )
    }

    func scaled(_ factor: Double) -> Macros {
        Macros(
            kcal: kcal * factor, protein: protein * factor,
            carbs: carbs * factor, fat: fat * factor
        )
    }
}

/// Pure nutrition arithmetic, ported line for line from suivinut's
/// `domain/nutrition.py` — the adaptive algorithm took three iterations to
/// get right over there, so the semantics are copied, not re-derived.
enum NutritionMath {
    /// Daily macro targets: kcal from the day type, protein and fat global,
    /// carbs deduced from what is left — `(kcal − 4P − 9L) / 4`, floored at 0.
    static func dailyTargets(
        kcalTarget: Int?, proteinG: Double, fatG: Double
    ) -> Macros? {
        guard let kcalTarget else { return nil }
        let kcal = Double(kcalTarget)
        let carbs = max(0, (kcal - 4 * proteinG - 9 * fatG) / 4)
        return Macros(kcal: kcal, protein: proteinG, carbs: carbs, fat: fatG)
    }

    static func mealTarget(daily: Macros, pct: Int) -> Macros {
        daily.scaled(Double(pct) / 100)
    }

    /// The day's remaining budget, each macro floored at zero — an exceeded
    /// margin reads as "nothing left", not as a negative allowance.
    static func remainingDay(daily: Macros, consumed: Macros) -> Macros {
        Macros(
            kcal: max(0, daily.kcal - consumed.kcal),
            protein: max(0, daily.protein - consumed.protein),
            carbs: max(0, daily.carbs - consumed.carbs),
            fat: max(0, daily.fat - consumed.fat)
        )
    }

    struct MealState {
        var pct: Int
        var started: Bool
        var consumed: Macros
    }

    /// Per-meal targets that adapt to what was actually eaten.
    ///
    /// A meal is *finished* as soon as a later meal is started. Finished
    /// meals keep their fixed plan share (to see how they compared to the
    /// plan). The current meal takes its share of the remaining budget with
    /// an unchanged formula — so its target does not jump when the first
    /// food lands in it. Upcoming (empty) meals split what is *really* left
    /// of the day, so eating exactly their target lands exactly on the
    /// day's goal whether earlier meals over- or under-shot.
    static func adaptiveMealTargets(
        daily: Macros?, meals: [MealState]
    ) -> [Macros?] {
        guard let daily else { return meals.map { _ in nil } }
        let count = meals.count
        let superseded = (0..<count).map { index in
            meals[(index + 1)...].contains { $0.started }
        }
        // What weighs on the budget without owning a target: finished meals
        // and 0 % slots. The current/upcoming meals' own intake stays in the
        // budget — it counts against their own target.
        let otherConsumed = (0..<count)
            .filter { superseded[$0] || meals[$0].pct <= 0 }
            .map { meals[$0].consumed }
            .reduce(.zero, +)
        let budget = remainingDay(daily: daily, consumed: otherConsumed)
        let inPlay = (0..<count).filter { !superseded[$0] && meals[$0].pct > 0 }
        let inPlayPct = inPlay.reduce(0) { $0 + meals[$1].pct }
        // The current meal is the last started one still in play — there can
        // only be one, anything before a started meal is superseded.
        let current = inPlay.last { meals[$0].started }
        let currentTarget: Macros?
        let currentConsumed: Macros
        if let current, inPlayPct > 0 {
            currentTarget = budget.scaled(
                Double(meals[current].pct) / Double(inPlayPct)
            )
            currentConsumed = meals[current].consumed
        } else {
            currentTarget = nil
            currentConsumed = .zero
        }
        let futureBudget = remainingDay(
            daily: daily, consumed: otherConsumed + currentConsumed
        )
        let futurePct = inPlay
            .filter { $0 != current && !meals[$0].started }
            .reduce(0) { $0 + meals[$1].pct }
        return (0..<count).map { index in
            let meal = meals[index]
            if meal.pct <= 0 { return nil }
            if superseded[index] { return mealTarget(daily: daily, pct: meal.pct) }
            if index == current { return currentTarget }
            return futurePct > 0
                ? futureBudget.scaled(Double(meal.pct) / Double(futurePct))
                : futureBudget
        }
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS sur les 11 tests.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionMath.swift Tests/NutritionMathTests.swift
git commit -m "feat(alimentation): calculs nutritionnels purs et cibles adaptatives"
```

---

### Task 4: SQLiteDatabase — accès SQLite minimal

**Files:**
- Create: `Cairn/Features/Nutrition/SQLiteDatabase.swift`
- Test: `Tests/SQLiteDatabaseTests.swift`

**Interfaces:**
- Consumes: rien (libsqlite3 système).
- Produces: `final class SQLiteDatabase` — `init(path: String, readOnly: Bool = false) throws`, `func execute(_ sql: String) throws`, `func rows(_ sql: String) throws -> [[String: Value]]` ; `enum Value: Equatable { case integer(Int64), real(Double), text(String), null }` avec accesseurs `intValue: Int?`, `int64Value: Int64?`, `doubleValue: Double?` (coerce integer→double), `stringValue: String?` ; `struct Error: Swift.Error`. Task 5 (import) l'utilise en lecture ; la phase 5 (catalogue) le réutilisera.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/SQLiteDatabaseTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "sqlite-test-\(UUID().uuidString).db").path
    }

    @Test("créer, insérer, relire avec les bons types")
    func roundTripsTypedValues() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute("""
            CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, kcal REAL, code TEXT);
            INSERT INTO t (name, kcal, code) VALUES ('Riz', 350.5, NULL);
            """)
        let rows = try db.rows("SELECT id, name, kcal, code FROM t")
        #expect(rows.count == 1)
        #expect(rows[0]["id"] == .integer(1))
        #expect(rows[0]["name"] == .text("Riz"))
        #expect(rows[0]["kcal"] == .real(350.5))
        #expect(rows[0]["code"] == .null)
    }

    @Test("les accesseurs coercent les entiers en double, pas l'inverse")
    func valueAccessorsCoerce() {
        #expect(SQLiteDatabase.Value.integer(42).doubleValue == 42.0)
        #expect(SQLiteDatabase.Value.integer(42).intValue == 42)
        #expect(SQLiteDatabase.Value.real(1.5).doubleValue == 1.5)
        #expect(SQLiteDatabase.Value.real(1.5).intValue == nil)
        #expect(SQLiteDatabase.Value.text("x").stringValue == "x")
        #expect(SQLiteDatabase.Value.null.stringValue == nil)
    }

    @Test("l'ouverture en lecture seule d'un fichier absent échoue")
    func readOnlyOpenOfMissingFileThrows() {
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try SQLiteDatabase(path: temporaryPath(), readOnly: true)
        }
    }

    @Test("écrire sur une base ouverte en lecture seule échoue")
    func writeOnReadOnlyThrows() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try SQLiteDatabase(path: path)
        try writer.execute("CREATE TABLE t (id INTEGER)")
        let reader = try SQLiteDatabase(path: path, readOnly: true)
        #expect(throws: SQLiteDatabase.Error.self) {
            try reader.execute("INSERT INTO t VALUES (1)")
        }
    }

    @Test("une requête sur une table absente échoue proprement")
    func queryOnMissingTableThrows() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try db.rows("SELECT * FROM absente")
        }
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/SQLiteDatabaseTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/SQLiteDatabase.swift
import Foundation
import SQLite3

/// The thinnest possible wrapper over the system SQLite: open, run, read
/// rows. It exists for the one-shot suivinut import and, later, the OFF
/// catalog — SwiftData owns everything else, so this deliberately has no
/// bindings, no statement cache, no migration story.
final class SQLiteDatabase {
    enum Value: Equatable {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null

        var int64Value: Int64? {
            if case let .integer(value) = self { return value }
            return nil
        }

        var intValue: Int? { int64Value.map(Int.init) }

        /// Integers coerce to double — SQLite columns are dynamically typed
        /// and a REAL column happily stores `80` as an integer.
        var doubleValue: Double? {
            switch self {
            case let .real(value): return value
            case let .integer(value): return Double(value)
            default: return nil
            }
        }

        var stringValue: String? {
            if case let .text(value) = self { return value }
            return nil
        }
    }

    struct Error: Swift.Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private var handle: OpaquePointer?

    init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "impossible d'ouvrir la base"
            sqlite3_close(handle)
            handle = nil
            throw Error(message: message)
        }
    }

    deinit { sqlite3_close(handle) }

    /// Statements that return nothing — DDL, INSERT. Several statements
    /// separated by `;` are fine, `sqlite3_exec` runs the batch.
    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK
        else {
            let message = errorPointer.map { String(cString: $0) }
                ?? "échec d'exécution"
            sqlite3_free(errorPointer)
            throw Error(message: message)
        }
    }

    /// All rows of a SELECT, keyed by column name. Materialising the whole
    /// result is fine for the volumes this reads — hundreds of journal rows;
    /// the catalog build in phase 5 will stream on its own terms.
    func rows(_ sql: String) throws -> [[String: Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK
        else {
            throw Error(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String: Value]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Value] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = value(of: statement, at: index)
            }
            result.append(row)
        }
        return result
    }

    private func value(of statement: OpaquePointer?, at index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(statement, index)))
        default:
            return .null
        }
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS sur les 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/SQLiteDatabase.swift Tests/SQLiteDatabaseTests.swift
git commit -m "feat(alimentation): accès SQLite minimal en lecture"
```

---

### Task 5: SuivinutImporter — import unique du journal

**Files:**
- Create: `Cairn/Features/Nutrition/SuivinutImporter.swift`
- Test: `Tests/SuivinutImporterTests.swift`

**Interfaces:**
- Consumes: `SQLiteDatabase` (Task 4), modèles (Task 2), `DateKey` (Task 1).
- Produces:
  - `@MainActor struct SuivinutImporter` — `init(context: ModelContext)`, `func run(journalPath: String) throws -> Summary`
  - `struct Summary: Equatable` — compteurs `dayTypes`, `mealSlots`, `days`, `entries`, `notes`, `recipes`, `favorites`, `weights` (Int) + `proteinTargetG`, `fatTargetG`, `weightGoalKg` (`Double?`) que l'appelant applique aux `@AppStorage`
  - `static func copyCatalog(nextTo journalURL: URL, to destinationDirectory: URL, fileManager: FileManager = .default) throws -> URL?`

Tout-ou-rien : toutes les lectures et insertions se font dans le contexte, puis un unique `context.save()`. Une erreur SQL ou un `meal_slot_id` inconnu jette **avant** la sauvegarde — le store n'est jamais partiellement importé.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/SuivinutImporterTests.swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("SuivinutImporter")
@MainActor
struct SuivinutImporterTests {
    /// A minimal but complete suivinut journal, built with the same schema
    /// as `schema_journal.sql` — the importer must survive the real thing.
    private func makeFixture(at path: String) throws {
        let db = try SQLiteDatabase(path: path)
        try db.execute("""
            CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE day_types (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL, kcal_target INTEGER NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE meal_slots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
                target_pct INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE days (
                date TEXT PRIMARY KEY,
                day_type_id INTEGER REFERENCES day_types(id));
            CREATE TABLE log_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL, meal_slot_id INTEGER NOT NULL,
                product_code TEXT, food_name TEXT NOT NULL,
                kcal_100g REAL NOT NULL, protein_100g REAL NOT NULL,
                carbs_100g REAL NOT NULL, fat_100g REAL NOT NULL,
                grams REAL NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE meal_notes (
                date TEXT NOT NULL, meal_slot_id INTEGER NOT NULL,
                note TEXT NOT NULL, PRIMARY KEY (date, meal_slot_id));
            CREATE TABLE recipes (
                id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                meal_slot_id INTEGER REFERENCES meal_slots(id));
            CREATE TABLE recipe_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                recipe_id INTEGER NOT NULL,
                food_name TEXT NOT NULL, product_code TEXT,
                kcal_100g REAL NOT NULL, protein_100g REAL NOT NULL,
                carbs_100g REAL NOT NULL, fat_100g REAL NOT NULL,
                grams REAL NOT NULL);
            CREATE TABLE weights (
                date TEXT PRIMARY KEY, weight_kg REAL NOT NULL, note TEXT);
            CREATE TABLE favorites (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                food_name TEXT NOT NULL, product_code TEXT,
                kcal_100g REAL NOT NULL, protein_100g REAL NOT NULL,
                carbs_100g REAL NOT NULL, fat_100g REAL NOT NULL,
                grams REAL NOT NULL);
            INSERT INTO favorites
                (food_name, product_code, kcal_100g, protein_100g,
                 carbs_100g, fat_100g, grams)
                VALUES ('Skyr', NULL, 57, 10, 4, 0.2, 150);
            INSERT INTO settings VALUES
                ('protein_target_g', '130'), ('fat_target_g', '66'),
                ('weight_goal_kg', '70'), ('theme', 'nord');
            INSERT INTO day_types (id, name, kcal_target, sort_order)
                VALUES (1, 'repos', 1750, 0), (2, 'sortie longue', 2950, 1);
            INSERT INTO meal_slots (id, name, sort_order, target_pct)
                VALUES (1, 'Petit-déj', 0, 28), (2, 'Dîner', 1, 39);
            INSERT INTO days VALUES ('2026-08-07', 2), ('2026-08-08', NULL);
            INSERT INTO log_entries
                (date, meal_slot_id, product_code, food_name, kcal_100g,
                 protein_100g, carbs_100g, fat_100g, grams, sort_order)
                VALUES
                ('2026-08-07', 1, '123', 'Flocons', 370, 13, 60, 7, 80, 0),
                ('2026-08-07', 2, NULL, 'Riz', 350, 7, 77, 1, 120, 0);
            INSERT INTO meal_notes VALUES ('2026-08-07', 1, 'avant footing');
            INSERT INTO recipes (id, name, meal_slot_id) VALUES (1, 'Porridge', 1);
            INSERT INTO recipe_items
                (recipe_id, food_name, product_code, kcal_100g, protein_100g,
                 carbs_100g, fat_100g, grams)
                VALUES (1, 'Flocons', '123', 370, 13, 60, 7, 80);
            INSERT INTO weights VALUES ('2026-08-07', 71.4, NULL);
            """)
    }

    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "journal-fixture-\(UUID().uuidString).db").path
    }

    @Test("tout le journal est importé et relié")
    func importsEverything() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try makeFixture(at: path)
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let summary = try SuivinutImporter(context: context).run(journalPath: path)

        #expect(summary.dayTypes == 2)
        #expect(summary.mealSlots == 2)
        #expect(summary.days == 2)
        #expect(summary.entries == 2)
        #expect(summary.notes == 1)
        #expect(summary.recipes == 1)
        #expect(summary.favorites == 1)
        #expect(summary.weights == 1)
        #expect(summary.proteinTargetG == 130)
        #expect(summary.fatTargetG == 66)
        #expect(summary.weightGoalKg == 70)

        // The relations survived the id remapping.
        let days = try context.fetch(FetchDescriptor<NutritionDay>())
        let longRun = days.first { $0.dateKeyRaw == "2026-08-07" }
        #expect(longRun?.dayType?.name == "sortie longue")
        #expect(days.first { $0.dateKeyRaw == "2026-08-08" }?.dayType == nil)
        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(entries.first { $0.foodName == "Flocons" }?.mealSlot?.name == "Petit-déj")
        #expect(entries.first { $0.foodName == "Flocons" }?.productCode == "123")
        let notes = try context.fetch(FetchDescriptor<MealNote>())
        #expect(notes[0].mealSlot?.name == "Petit-déj")
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        #expect(recipes[0].items?.count == 1)
        #expect(recipes[0].mealSlot?.name == "Petit-déj")
    }

    @Test("une base invalide ne laisse rien dans le store")
    func brokenDatabaseImportsNothing() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        // A database missing most tables: reading log_entries must throw.
        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)")
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        #expect(throws: (any Error).self) {
            try SuivinutImporter(context: context).run(journalPath: path)
        }
        #expect(try context.fetch(FetchDescriptor<DayType>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).isEmpty)
    }

    @Test("une entrée pointant un repas inconnu fait échouer tout l'import")
    func unknownSlotAbortsTheWholeImport() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try makeFixture(at: path)
        let db = try SQLiteDatabase(path: path)
        try db.execute("""
            INSERT INTO log_entries
                (date, meal_slot_id, food_name, kcal_100g, protein_100g,
                 carbs_100g, fat_100g, grams)
                VALUES ('2026-08-07', 99, 'Fantôme', 1, 1, 1, 1, 1)
            """)
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        #expect(throws: (any Error).self) {
            try SuivinutImporter(context: context).run(journalPath: path)
        }
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).isEmpty)
    }

    @Test("copyCatalog copie le off.db voisin du journal")
    func copiesSiblingCatalog() throws {
        let fileManager = FileManager.default
        let source = fileManager.temporaryDirectory
            .appending(path: "suivinut-src-\(UUID().uuidString)")
        let destination = fileManager.temporaryDirectory
            .appending(path: "cairn-dst-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: source)
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        let journal = source.appending(path: "journal.db")
        try Data("journal".utf8).write(to: journal)
        try Data("catalogue".utf8).write(to: source.appending(path: "off.db"))

        let copied = try SuivinutImporter.copyCatalog(
            nextTo: journal, to: destination
        )
        #expect(copied != nil)
        #expect(
            try String(contentsOf: destination.appending(path: "off.db"), encoding: .utf8)
                == "catalogue"
        )
    }

    @Test("copyCatalog rend nil quand aucun off.db n'existe")
    func returnsNilWithoutCatalog() throws {
        let fileManager = FileManager.default
        let source = fileManager.temporaryDirectory
            .appending(path: "suivinut-empty-\(UUID().uuidString)")
        let destination = fileManager.temporaryDirectory
            .appending(path: "cairn-dst-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: source)
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        let journal = source.appending(path: "journal.db")
        try Data("journal".utf8).write(to: journal)

        let copied = try SuivinutImporter.copyCatalog(nextTo: journal, to: destination)
        #expect(copied == nil)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/SuivinutImporterTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/SuivinutImporter.swift
import Foundation
import SwiftData

/// One-shot import of a suivinut `journal.db` into the SwiftData store.
///
/// All-or-nothing: every row is read and inserted into the context first,
/// and a single `save()` commits the lot. Any SQL error, missing table or
/// dangling reference throws *before* the save — the store is never left
/// half-imported, which matters because the import banner only shows while
/// the store is empty.
@MainActor
struct SuivinutImporter {
    struct Summary: Equatable {
        var dayTypes = 0
        var mealSlots = 0
        var days = 0
        var entries = 0
        var notes = 0
        var recipes = 0
        var favorites = 0
        var weights = 0
        var proteinTargetG: Double?
        var fatTargetG: Double?
        var weightGoalKg: Double?
    }

    struct ImportError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    let context: ModelContext

    func run(journalPath: String) throws -> Summary {
        let db = try SQLiteDatabase(path: journalPath, readOnly: true)
        var summary = Summary()

        // Suivinut ids never enter the store — they only live long enough
        // to rebuild the relations as object references.
        var dayTypes: [Int64: DayType] = [:]
        for row in try db.rows(
            "SELECT id, name, kcal_target, sort_order FROM day_types"
        ) {
            let model = DayType(
                name: row["name"]?.stringValue ?? "",
                kcalTarget: row["kcal_target"]?.intValue ?? 0,
                sortOrder: row["sort_order"]?.intValue ?? 0
            )
            context.insert(model)
            if let id = row["id"]?.int64Value { dayTypes[id] = model }
            summary.dayTypes += 1
        }

        var slots: [Int64: MealSlot] = [:]
        for row in try db.rows(
            "SELECT id, name, sort_order, target_pct FROM meal_slots"
        ) {
            let model = MealSlot(
                name: row["name"]?.stringValue ?? "",
                sortOrder: row["sort_order"]?.intValue ?? 0,
                targetPct: row["target_pct"]?.intValue ?? 0
            )
            context.insert(model)
            if let id = row["id"]?.int64Value { slots[id] = model }
            summary.mealSlots += 1
        }

        func slot(for row: [String: SQLiteDatabase.Value], table: String) throws -> MealSlot {
            guard let id = row["meal_slot_id"]?.int64Value, let slot = slots[id]
            else {
                throw ImportError(
                    message: "\(table) référence un repas inconnu — import annulé."
                )
            }
            return slot
        }

        func dateKey(for row: [String: SQLiteDatabase.Value], table: String) throws -> DateKey {
            guard let raw = row["date"]?.stringValue, let key = DateKey(raw: raw)
            else {
                throw ImportError(
                    message: "\(table) contient une date invalide — import annulé."
                )
            }
            return key
        }

        for row in try db.rows("SELECT date, day_type_id FROM days") {
            let dayType = row["day_type_id"]?.int64Value.flatMap { dayTypes[$0] }
            context.insert(
                NutritionDay(dateKey: try dateKey(for: row, table: "days"), dayType: dayType)
            )
            summary.days += 1
        }

        for row in try db.rows("""
            SELECT date, meal_slot_id, product_code, food_name, kcal_100g,
                   protein_100g, carbs_100g, fat_100g, grams, sort_order
            FROM log_entries
            """) {
            context.insert(FoodEntry(
                dateKey: try dateKey(for: row, table: "log_entries"),
                mealSlot: try slot(for: row, table: "log_entries"),
                foodName: row["food_name"]?.stringValue ?? "",
                kcal100: row["kcal_100g"]?.doubleValue ?? 0,
                protein100: row["protein_100g"]?.doubleValue ?? 0,
                carbs100: row["carbs_100g"]?.doubleValue ?? 0,
                fat100: row["fat_100g"]?.doubleValue ?? 0,
                grams: row["grams"]?.doubleValue ?? 0,
                sortOrder: row["sort_order"]?.intValue ?? 0,
                productCode: row["product_code"]?.stringValue
            ))
            summary.entries += 1
        }

        for row in try db.rows("SELECT date, meal_slot_id, note FROM meal_notes") {
            context.insert(MealNote(
                dateKey: try dateKey(for: row, table: "meal_notes"),
                mealSlot: try slot(for: row, table: "meal_notes"),
                note: row["note"]?.stringValue ?? ""
            ))
            summary.notes += 1
        }

        var recipes: [Int64: Recipe] = [:]
        for row in try db.rows("SELECT id, name, meal_slot_id FROM recipes") {
            let slot = row["meal_slot_id"]?.int64Value.flatMap { slots[$0] }
            let model = Recipe(
                name: row["name"]?.stringValue ?? "", mealSlot: slot
            )
            context.insert(model)
            if let id = row["id"]?.int64Value { recipes[id] = model }
            summary.recipes += 1
        }

        for row in try db.rows("""
            SELECT recipe_id, food_name, product_code, kcal_100g,
                   protein_100g, carbs_100g, fat_100g, grams
            FROM recipe_items
            """) {
            guard let recipeID = row["recipe_id"]?.int64Value,
                  let recipe = recipes[recipeID]
            else {
                throw ImportError(
                    message: "recipe_items référence une recette inconnue — import annulé."
                )
            }
            let item = RecipeItem(
                foodName: row["food_name"]?.stringValue ?? "",
                kcal100: row["kcal_100g"]?.doubleValue ?? 0,
                protein100: row["protein_100g"]?.doubleValue ?? 0,
                carbs100: row["carbs_100g"]?.doubleValue ?? 0,
                fat100: row["fat_100g"]?.doubleValue ?? 0,
                grams: row["grams"]?.doubleValue ?? 0,
                productCode: row["product_code"]?.stringValue
            )
            item.recipe = recipe
            context.insert(item)
        }

        for row in try db.rows("""
            SELECT food_name, product_code, kcal_100g, protein_100g,
                   carbs_100g, fat_100g, grams
            FROM favorites
            """) {
            context.insert(FavoriteFood(
                foodName: row["food_name"]?.stringValue ?? "",
                kcal100: row["kcal_100g"]?.doubleValue ?? 0,
                protein100: row["protein_100g"]?.doubleValue ?? 0,
                carbs100: row["carbs_100g"]?.doubleValue ?? 0,
                fat100: row["fat_100g"]?.doubleValue ?? 0,
                grams: row["grams"]?.doubleValue ?? 0,
                productCode: row["product_code"]?.stringValue
            ))
            summary.favorites += 1
        }

        for row in try db.rows("SELECT date, weight_kg, note FROM weights") {
            context.insert(WeightEntry(
                dateKey: try dateKey(for: row, table: "weights"),
                weightKg: row["weight_kg"]?.doubleValue ?? 0,
                note: row["note"]?.stringValue
            ))
            summary.weights += 1
        }

        for row in try db.rows("SELECT key, value FROM settings") {
            let value = row["value"]?.stringValue.flatMap(Double.init)
            switch row["key"]?.stringValue {
            case "protein_target_g": summary.proteinTargetG = value
            case "fat_target_g": summary.fatTargetG = value
            case "weight_goal_kg": summary.weightGoalKg = value
            default: break
            }
        }

        try context.save()
        return summary
    }

    /// Copies an existing suivinut `off.db` — next to the imported journal,
    /// or from the default suivinut home — so food search works immediately,
    /// without waiting for the 1 GB catalog download of phase 5. Returns nil
    /// when no catalog is found: that is a normal state, not an error.
    static func copyCatalog(
        nextTo journalURL: URL,
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL? {
        let candidates = [
            journalURL.deletingLastPathComponent().appending(path: "off.db"),
            fileManager.homeDirectoryForCurrentUser
                .appending(path: ".local/share/suivinut/off.db"),
        ]
        guard let source = candidates.first(
            where: { fileManager.fileExists(atPath: $0.path) }
        ) else { return nil }
        try fileManager.createDirectory(
            at: destinationDirectory, withIntermediateDirectories: true
        )
        let destination = destinationDirectory.appending(path: "off.db")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS sur les 6 tests. Note : si le test « tout-ou-rien » échoue parce que des objets insérés avant l'erreur restent dans le contexte, appeler `context.rollback()` dans un `catch` de `run` avant de relancer l'erreur — c'est le comportement attendu (rien de visible après échec).

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/SuivinutImporter.swift Tests/SuivinutImporterTests.swift
git commit -m "feat(alimentation): import unique du journal suivinut"
```

---

### Task 6: NutritionDayModel — modèle d'affichage du jour

**Files:**
- Create: `Cairn/Features/Nutrition/NutritionDayModel.swift`
- Test: `Tests/NutritionDayModelTests.swift`

**Interfaces:**
- Consumes: modèles (Task 2), `NutritionMath`/`Macros` (Task 3).
- Produces:

```swift
struct NutritionDayModel: Equatable {
    struct Row: Equatable {
        var name: String
        var grams: Double
        var macros: Macros
    }
    struct Meal: Equatable {
        var slotName: String
        var rows: [Row]
        var consumed: Macros
        var target: Macros?
        var note: String?
    }
    var dayTypeName: String?
    var daily: Macros?
    var consumed: Macros
    var meals: [Meal]

    @MainActor
    static func compute(
        entries: [FoodEntry], slots: [MealSlot], notes: [MealNote],
        dayType: DayType?, proteinTargetG: Double, fatTargetG: Double
    ) -> NutritionDayModel
}
```

La vue (Task 8) appelle `compute` directement dans `body`, comme `StatisticsView` appelle `ActivityStatistics.compute`. Sémantique : repas ordonnés par `sortOrder` de slot, entrées d'un repas ordonnées par leur `sortOrder`, `consumed` global = somme de toutes les entrées, cibles par repas via `adaptiveMealTargets` (`started` = le repas a au moins une entrée).

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/NutritionDayModelTests.swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionDayModel")
@MainActor
struct NutritionDayModelTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("les repas sortent ordonnés avec leurs entrées, totaux et notes")
    func buildsOrderedMeals() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let key = DateKey(raw: "2026-08-08")!
        let oats = FoodEntry(
            dateKey: key, mealSlot: breakfast, foodName: "Flocons",
            kcal100: 370, protein100: 13, carbs100: 60, fat100: 7,
            grams: 100, sortOrder: 1
        )
        let skyr = FoodEntry(
            dateKey: key, mealSlot: breakfast, foodName: "Skyr",
            kcal100: 57, protein100: 10, carbs100: 4, fat100: 0,
            grams: 100, sortOrder: 0
        )
        context.insert(oats)
        context.insert(skyr)
        let note = MealNote(dateKey: key, mealSlot: breakfast, note: "avant footing")
        context.insert(note)
        let dayType = DayType(name: "repos", kcalTarget: 1750)
        context.insert(dayType)

        let model = NutritionDayModel.compute(
            entries: [oats, skyr], slots: [dinner, breakfast], notes: [note],
            dayType: dayType, proteinTargetG: 130, fatTargetG: 66
        )

        #expect(model.dayTypeName == "repos")
        #expect(model.meals.count == 2)
        // Slots ordered by sortOrder even when handed shuffled.
        #expect(model.meals[0].slotName == "Petit-déj")
        // Entries ordered by their own sortOrder: Skyr (0) before Flocons (1).
        #expect(model.meals[0].rows.map(\.name) == ["Skyr", "Flocons"])
        #expect(model.meals[0].note == "avant footing")
        #expect(model.meals[1].rows.isEmpty)
        #expect(model.meals[1].note == nil)
        // 370 + 57 for 100 g each.
        #expect(abs(model.consumed.kcal - 427) < 0.001)
        #expect(abs(model.meals[0].consumed.protein - 23) < 0.001)
    }

    @Test("la cible du jour vient du jour-type et les repas ont leur cible adaptative")
    func computesTargets() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let dayType = DayType(name: "repos", kcalTarget: 2000)
        context.insert(dayType)

        let model = NutritionDayModel.compute(
            entries: [], slots: [breakfast, dinner], notes: [],
            dayType: dayType, proteinTargetG: 100, fatTargetG: 60
        )

        #expect(model.daily?.kcal == 2000)
        // No meal started: each upcoming meal splits the full day pro rata.
        #expect(abs((model.meals[0].target?.kcal ?? 0) - 2000 * 28 / 67) < 0.001)
        #expect(abs((model.meals[1].target?.kcal ?? 0) - 2000 * 39 / 67) < 0.001)
    }

    @Test("sans jour-type : pas de cible du jour ni de cibles de repas")
    func noDayTypeMeansNoTargets() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)

        let model = NutritionDayModel.compute(
            entries: [], slots: [slot], notes: [],
            dayType: nil, proteinTargetG: 130, fatTargetG: 66
        )

        #expect(model.daily == nil)
        #expect(model.meals[0].target == nil)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionDayModelTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/NutritionDayModel.swift
import Foundation
import SwiftData

/// Everything the day screen shows, computed in one pure pass — the same
/// split as `ActivityStatistics`: the view stays declarative, the arithmetic
/// stays testable without UI.
struct NutritionDayModel: Equatable {
    struct Row: Equatable {
        var name: String
        var grams: Double
        var macros: Macros
    }

    struct Meal: Equatable {
        var slotName: String
        var rows: [Row]
        var consumed: Macros
        var target: Macros?
        var note: String?
    }

    var dayTypeName: String?
    var daily: Macros?
    var consumed: Macros
    var meals: [Meal]

    @MainActor
    static func compute(
        entries: [FoodEntry], slots: [MealSlot], notes: [MealNote],
        dayType: DayType?, proteinTargetG: Double, fatTargetG: Double
    ) -> NutritionDayModel {
        let orderedSlots = slots.sorted { $0.sortOrder < $1.sortOrder }
        // Grouped by object identity: entries reference the slot itself, so
        // no id juggling is needed.
        let entriesBySlot = Dictionary(grouping: entries) {
            $0.mealSlot?.persistentModelID
        }
        let daily = NutritionMath.dailyTargets(
            kcalTarget: dayType?.kcalTarget,
            proteinG: proteinTargetG, fatG: fatTargetG
        )
        let mealEntries = orderedSlots.map { slot in
            (entriesBySlot[slot.persistentModelID] ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
        }
        let mealConsumed = mealEntries.map { entries in
            entries.map(Macros.init(of:)).reduce(.zero, +)
        }
        let targets = NutritionMath.adaptiveMealTargets(
            daily: daily,
            meals: zip(orderedSlots, zip(mealEntries, mealConsumed)).map {
                slot, pair in
                NutritionMath.MealState(
                    pct: slot.targetPct, started: !pair.0.isEmpty,
                    consumed: pair.1
                )
            }
        )
        let meals = orderedSlots.enumerated().map { index, slot in
            Meal(
                slotName: slot.name,
                rows: mealEntries[index].map {
                    Row(name: $0.foodName, grams: $0.grams, macros: Macros(of: $0))
                },
                consumed: mealConsumed[index],
                target: targets[index],
                note: notes.first {
                    $0.mealSlot?.persistentModelID == slot.persistentModelID
                }?.note
            )
        }
        return NutritionDayModel(
            dayTypeName: dayType?.name,
            daily: daily,
            consumed: mealConsumed.reduce(.zero, +),
            meals: meals
        )
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS sur les 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionDayModel.swift Tests/NutritionDayModelTests.swift
git commit -m "feat(alimentation): modèle d'affichage pur du jour"
```

---

### Task 7: NutritionSeed — valeurs par défaut sans import

**Files:**
- Create: `Cairn/Features/Nutrition/NutritionSeed.swift`
- Test: `Tests/NutritionSeedTests.swift`

**Interfaces:**
- Consumes: `DayType`, `MealSlot` (Task 2).
- Produces: `enum NutritionSeed` — `@MainActor static func runIfEmpty(in context: ModelContext) throws`. La vue (Task 8) l'appelle quand l'utilisateur choisit « Commencer sans importer ».

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/NutritionSeedTests.swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionSeed")
@MainActor
struct NutritionSeedTests {
    @Test("le semis crée les repas et jours-types de suivinut")
    func seedsDefaults() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        try NutritionSeed.runIfEmpty(in: context)

        let slots = try context.fetch(FetchDescriptor<MealSlot>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(slots.map(\.name) == ["Petit-déj", "Déjeuner", "Collation", "Dîner"])
        #expect(slots.map(\.targetPct) == [28, 33, 0, 39])
        let dayTypes = try context.fetch(FetchDescriptor<DayType>())
        #expect(dayTypes.count == 4)
        #expect(dayTypes.contains { $0.name == "repos" && $0.kcalTarget == 1800 })
    }

    @Test("le semis ne double pas des repas existants")
    func doesNotDuplicate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        context.insert(MealSlot(name: "Unique", sortOrder: 0, targetPct: 100))
        try context.save()

        try NutritionSeed.runIfEmpty(in: context)
        #expect(try context.fetch(FetchDescriptor<MealSlot>()).count == 1)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionSeedTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/NutritionSeed.swift
import Foundation
import SwiftData

/// The starter journal for someone who skips the suivinut import — the same
/// defaults as suivinut's `_seed()`, so both starting points feel identical.
enum NutritionSeed {
    @MainActor
    static func runIfEmpty(in context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<MealSlot>()).isEmpty else {
            return
        }
        let slots = [
            ("Petit-déj", 28), ("Déjeuner", 33), ("Collation", 0), ("Dîner", 39),
        ]
        for (index, slot) in slots.enumerated() {
            context.insert(
                MealSlot(name: slot.0, sortOrder: index, targetPct: slot.1)
            )
        }
        let dayTypes = [
            ("repos", 1800), ("lever", 1900), ("qualité", 2100),
            ("sortie longue", 2500),
        ]
        for (index, dayType) in dayTypes.enumerated() {
            context.insert(
                DayType(
                    name: dayType.0, kcalTarget: dayType.1, sortOrder: index
                )
            )
        }
        try context.save()
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS sur les 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionSeed.swift Tests/NutritionSeedTests.swift
git commit -m "feat(alimentation): semis des repas et jours-types par défaut"
```

---

### Task 8: Écran Alimentation en lecture et entrée sidebar

**Files:**
- Create: `Cairn/Features/Nutrition/NutritionSettings.swift`, `Cairn/Features/Nutrition/MacroGauge.swift`, `Cairn/Features/Nutrition/NutritionDayView.swift`
- Modify: `Cairn/App/SidebarView.swift:4-8` (enum) et `:36-37` (label), `Cairn/App/RootView.swift:266-268` (helpers) et `:286-318` (routage), `Cairn/Features/Shared/Formatters.swift` (ajout `fullDate`)

**Interfaces:**
- Consumes: `NutritionDayModel.compute` (Task 6), `SuivinutImporter` (Task 5), `NutritionSeed` (Task 7), `DateKey` (Task 1), `Format.longDate` (existant).
- Produces: `SidebarItem.nutrition`, `NutritionDayView` (vue sans paramètres, tout vient de `@Query`), `enum NutritionSettings` avec `proteinTargetKey`/`fatTargetKey`/`weightGoalKey` et les défauts `130.0`/`66.0`/`70.0` — les phases 2+ les réutilisent.

- [ ] **Step 1: Constantes de réglages**

```swift
// Cairn/Features/Nutrition/NutritionSettings.swift
import Foundation

/// AppStorage keys for the nutrition targets — held here so no key literal
/// is ever duplicated, the same rule as `StatsPeriod.storageKey`. Defaults
/// match suivinut's seed; a suivinut import overwrites them with the
/// journal's own values.
enum NutritionSettings {
    static let proteinTargetKey = "nutritionProteinTargetG"
    static let fatTargetKey = "nutritionFatTargetG"
    static let weightGoalKey = "nutritionWeightGoalKg"

    static let defaultProteinTargetG = 130.0
    static let defaultFatTargetG = 66.0
    static let defaultWeightGoalKg = 70.0
}
```

- [ ] **Step 2: Jauge macro**

```swift
// Cairn/Features/Nutrition/MacroGauge.swift
import SwiftUI

/// One "consumed / target" figure with a thin progress bar — the unit of
/// the day's summary row. System colours only; red is reserved for an
/// exceeded target, which is the one state that must jump out.
struct MacroGauge: View {
    let title: String
    let consumed: Double
    let target: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(figure).font(.title3.monospacedDigit())
            if let target, target > 0 {
                ProgressView(value: min(consumed / target, 1))
                    .tint(consumed > target ? .red : .accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var figure: String {
        guard let target else { return "\(rounded(consumed)) \(unit)" }
        return "\(rounded(consumed)) / \(rounded(target)) \(unit)"
    }

    private func rounded(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}
```

- [ ] **Step 3: Formateur de date sans heure**

`Format.longDate` embarque l'heure (`timeStyle: .short`) — sur un jour de
journal elle afficherait « à 00:00 ». Ajouter dans `Cairn/Features/Shared/Formatters.swift`,
à côté des autres formateurs de date :

```swift
    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    /// Weekday and full date, no time — the food journal is keyed on
    /// calendar days, an hour would be an invention.
    static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }
```

- [ ] **Step 4: La vue du jour**

```swift
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

    var body: some View {
        if slots.isEmpty {
            onboarding
        } else {
            journal
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
                ForEach(Array(model.meals.enumerated()), id: \.offset) {
                    _, meal in
                    mealSection(meal)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(Format.fullDate(dateKey.date()).capitalized)
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
            if let dayTypeName = model.dayTypeName {
                Text(dayTypeName)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            } else {
                Text("Aucun jour-type")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
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

    // mealSection, onboarding et import suivent — même fichier, blocs
    // ci-dessous.
```

**Suite du même fichier — les sections de repas :**

```swift
    private func mealSection(_ meal: NutritionDayModel.Meal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meal.slotName).font(.headline)
                Spacer()
                Text(mealFigure(meal))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                    ForEach(Array(meal.rows.enumerated()), id: \.offset) { _, row in
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
```

**Onboarding et import (dans le même fichier) :**

```swift
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
            if let importMessage {
                Text(importMessage).foregroundStyle(.secondary)
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
```

- [ ] **Step 5: Sidebar et routage**

Dans `Cairn/App/SidebarView.swift`, l'enum devient :

```swift
enum SidebarItem: Hashable {
    case all
    case globalMap
    case statistics
    case nutrition
}
```

et sous le label Statistiques (ligne 36-37) :

```swift
                Label("Statistiques", systemImage: "chart.bar")
                    .tag(SidebarItem.statistics)
                Label("Alimentation", systemImage: "fork.knife")
                    .tag(SidebarItem.nutrition)
```

Dans `Cairn/App/RootView.swift`, à côté de `showsStatistics` (ligne 266-268) :

```swift
    private var showsNutrition: Bool { sidebarSelection == .nutrition }
```

et dans `splitView`, une branche après `showsStatistics` (avant le `else` final) :

```swift
                } else if showsNutrition {
                    NutritionDayView()
                        .vimKeys(performOutsideTheList)
                } else {
```

- [ ] **Step 6: Builder et lancer la suite complète**

Run:
```bash
xcodegen generate && xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | tail -5
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests 2>&1 | tail -5
```
Expected: build OK, tous les tests passent (les nouveaux et les ~47 suites existantes).

- [ ] **Step 7: Vérification visuelle**

Lancer l'app (`open build/Build/Products/Debug/Cairn.app` ou depuis Xcode), cliquer « Alimentation » dans la sidebar :
- l'écran d'onboarding s'affiche (store vide) avec les deux boutons ;
- importer le vrai journal (`~/Library/Mobile Documents/com~apple~CloudDocs/suivinut/journal.db`) **uniquement si l'utilisateur le demande** — sinon tester avec « Commencer sans importer » sur le store de démo (`STRAVALOCAL_DEMO=1`) pour ne pas toucher au vrai store ;
- naviguer entre les jours avec ‹ / ›, vérifier récap, repas, cibles.

- [ ] **Step 8: Commit**

```bash
git add Cairn/Features/Nutrition/ Cairn/App/SidebarView.swift Cairn/App/RootView.swift Cairn/Features/Shared/Formatters.swift
git commit -m "feat(alimentation): écran du jour en lecture et entrée sidebar"
```

---

## Après cette phase

Phase 2 (plan séparé) : sheet d'ajout d'aliment (recherche FTS5 sur le `off.db` copié, saisie manuelle, grammes), édition/suppression/réordonnancement des entrées, choix du jour-type depuis l'écran. Les interfaces à respecter sont celles produites par les tasks 1–8 ci-dessus.
