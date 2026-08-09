# Alimentation — Phase 6 : clavier, colonne détail, drag et finitions

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clore la spec : navigation clavier (`gn`/`gp`, `a`, `w`, Échap→aujourd'hui), mini-calendrier + panneau stats dans la colonne détail, drag de réordonnancement des aliments, et le solde des reliquats des phases 2-5.

**Architecture:** Les commandes d'écran (`a`, `w`) deviennent des `VimCommand` que chaque écran de journal intercepte dans sa fermeture `vimKeys` avant de déléguer au routage fenêtre. L'état du jour affiché remonte dans `RootView` pour être partagé entre l'écran Alimentation et le nouveau `NutritionSidePanel` de la colonne détail (qui remplace aussi le volet d'activité résiduel). Le drag porte `place_entry_after` de suivinut.

**Tech Stack:** Swift 6, SwiftUI (Transferable pour le drag), SwiftData, Swift Testing. Aucune dépendance externe.

**Spec :** `docs/specs/2026-08-08-alimentation-design.md` (§5 colonne détail + drag, §9 message d'erreur de recherche, §11 phase 6). Reliquats intégrés : `inFlight` du finding parqué en phase 5, `checkCancellation` avant le rebuild FTS, réutilisation du gz après un échec de build, garde NaN de la progression, formatteur signé 2 décimales, `applyRecipe` en une sauvegarde, extraction du flux d'import dupliqué, comparaison `DateKey` dans `WeightStats.window`, amendement de spec (réordonnancement des jours-types retiré).

## Global Constraints

- macOS 15.0 minimum, Swift 6.0 strict, `@MainActor` sur tout ce qui touche `ModelContext`.
- Aucune dépendance externe. Identifiants/commentaires **anglais**, chaînes visibles **français**, commentaires « pourquoi ».
- `monospacedDigit` sur les chiffres, couleurs système uniquement (vert = favorable, rouge = défavorable, comme le panneau suivinut).
- Après **tout ajout de fichier source** : `xcodegen generate` avant de builder.
- Tests : Swift Testing, noms en français. Commande type :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/VimKeyBufferTests 2>&1 | tail -5
  ```
- Commits : Conventional Commits en français, scopes `clavier` / `alimentation` / `catalogue` / `poids` selon la zone.
- Sémantique suivinut **à l'identique** pour le portage restant : `place_entry_after` renumérote tout le (date, repas) 0..n et est sans effet si la cible est absente ou d'un autre repas ; le panneau stats moyenne les apports sur les jours **enregistrés** de la fenêtre de 7 jours (pas sur 7) ; la régularité du mois = jours enregistrés depuis le 1er / jours écoulés ; Échap sur le jour = retour à aujourd'hui.

---

### Task 1: Clavier — gn/gp, a, w

**Files:**
- Modify: `Cairn/Features/Keyboard/VimCommand.swift` (cases + table g + `actsOnActivities`)
- Modify: `Cairn/App/RootView.swift` (`perform` : cases no-op)
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift` (interception + sheet pesée)
- Modify: `Cairn/Features/Nutrition/WeightView.swift` (interception)
- Modify: `Cairn/Features/Keyboard/KeyboardHelpSheet.swift`, `README.md:273+` (documentation)
- Test: `Tests/VimKeyBufferTests.swift` (ajouts)

**Interfaces:**
- Produces: `VimCommand.addFood` (touche `a`), `VimCommand.newWeighIn` (touche `w`), `.section(.nutrition)` (`gn`), `.section(.weight)` (`gp`). Les écrans de journal interceptent `.addFood`/`.newWeighIn` dans leur fermeture `vimKeys` ; partout ailleurs ces commandes sont des no-op silencieux.

- [ ] **Step 1: Tests qui échouent** (ajouts dans `VimKeyBufferTests`)

```swift
    @Test("gn et gp rejoignent les écrans du journal")
    func gPrefixReachesJournalSections() {
        #expect(run("gn") == [.section(.nutrition)])
        #expect(run("gp") == [.section(.weight)])
    }

    @Test("a et w déclenchent l'ajout, le compte est ignoré")
    func addFoodAndWeighIn() {
        #expect(run("a") == [.addFood])
        #expect(run("w") == [.newWeighIn])
        // Un compte n'a pas de sens sur une ouverture de sheet.
        #expect(run("3a") == [.addFood])
    }

    @Test("les commandes du journal ne sont pas des commandes d'activité")
    func journalCommandsAreNotActivityBound() {
        #expect(!VimCommand.addFood.actsOnActivities)
        #expect(!VimCommand.newWeighIn.actsOnActivities)
    }
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

`VimCommand.swift` :
- enum : ajouter, après `case showHelp` :

```swift
    /// Open the add-food sheet (nutrition screen) or a new weigh-in (weight
    /// screen). Screen-local: the journal views intercept these before
    /// forwarding to the window; anywhere else they are silent no-ops.
    case addFood
    case newWeighIn
```

- `actsOnActivities` : ajouter `.addFood, .newWeighIn` à la branche `false`.
- table `g` (dans `accept`, bloc `awaitingG`) : après `case "s"` :

```swift
            case "n": return .section(.nutrition)
            case "p": return .section(.weight)
```

- table à une touche : après `case "t"` :

```swift
        case "a": _ = takeCount(); return .addFood
        case "w": _ = takeCount(); return .newWeighIn
```

`RootView.swift`, dans `perform(_:)` (le switch) :

```swift
        case .addFood, .newWeighIn:
            // Reaching here means no journal screen intercepted them: the
            // list, map or statistics are showing, where they mean nothing.
            break
```

`NutritionDayView.swift` :
- États : `@State private var isAddingWeight = false` (+ l'ajouter à `isPresentingModal`) et `@Query(sort: \WeightEntry.dateKeyRaw) private var weights: [WeightEntry]`.
- La fermeture `vimKeys` intercepte avant de déléguer — remplacer `.vimKeys(enabled: !isPresentingModal, onCommand)` par :

```swift
        .vimKeys(enabled: !isPresentingModal) { command in
            switch command {
            case .addFood:
                // suivinut's `a` targets the meal under the cursor; without a
                // cursor, the first meal is the least surprising target and
                // the sheet's header names it.
                if let first = slots.first { addTargetSlot = first }
                return true
            case .newWeighIn:
                isAddingWeight = true
                return true
            default:
                return onCommand(command)
            }
        }
```

- Présentation (à côté des autres sheets) :

```swift
        .sheet(isPresented: $isAddingWeight) {
            WeightEntrySheet(
                existing: nil,
                defaultWeightKg: weights.last?.weightKg ?? weightGoal
            )
        }
```

`WeightView.swift` — même motif, remplacer `.vimKeys(enabled: !isPresentingModal, onCommand)` par :

```swift
        .vimKeys(enabled: !isPresentingModal) { command in
            switch command {
            case .addFood, .newWeighIn:
                // Both keys open the same sheet here: on the weight screen,
                // "add" can only mean a weigh-in.
                isAddingEntry = true
                return true
            default:
                return onCommand(command)
            }
        }
```

`KeyboardHelpSheet.swift` : dans le groupe « Changer de vue », après `("gs", …)` :

```swift
            ("gn", "alimentation"),
            ("gp", "poids"),
```

et un nouveau groupe après « Agir sur la sélection » :

```swift
        Group(title: "Journal alimentaire", rows: [
            ("a", "ajouter — un aliment sur Alimentation, une pesée sur Poids"),
            ("w", "nouvelle pesée"),
        ]),
```

(passer le `frame` de la sheet de `height: 460` à `height: 540` pour absorber le groupe.)

`README.md`, section « Raccourcis clavier » (l. 273+) : ajouter les mêmes quatre raccourcis aux listes existantes, dans le style des lignes voisines.

- [ ] **Step 4: Vérifier le succès** — `VimKeyBufferTests` puis suite complète (le build valide les vues).

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Keyboard/ Cairn/App/RootView.swift Cairn/Features/Nutrition/NutritionDayView.swift Cairn/Features/Nutrition/WeightView.swift README.md Tests/VimKeyBufferTests.swift
git commit -m "feat(clavier): gn/gp rejoignent le journal, a et w ouvrent les saisies"
```

---

### Task 2: Catalogue — reliquats de la phase 5

**Files:**
- Modify: `Cairn/Features/Nutrition/CatalogUpdater.swift`, `Cairn/Features/Nutrition/CatalogBuilder.swift`, `Cairn/Features/Nutrition/FileDownloader.swift`, `Cairn/Features/Nutrition/NutritionSettingsView.swift`, `Cairn/Features/Nutrition/WeightStats.swift`
- Test: `Tests/CatalogUpdaterTests.swift` (ajout)

**Interfaces:** inchangées — durcissements internes uniquement.

- [ ] **Step 1: Test qui échoue** (ajout dans `CatalogUpdaterTests`, suite déjà `.serialized`)

```swift
    @Test("un gz complet en cache saute le téléchargement")
    func existingCacheSkipsDownload() async throws {
        let cache = CatalogUpdater.cacheURL
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("gz factice".utf8).write(to: cache)
        defer { try? FileManager.default.removeItem(at: cache) }

        let updater = CatalogUpdater(
            download: { _, _, _ in
                Issue.record("le téléchargement ne devait pas être appelé")
            },
            build: { _, _, _, _ in 7 }
        )
        updater.start()
        await updater.waitUntilFinished()
        #expect(updater.phase == .done(count: 7))
    }
```

- [ ] **Step 2: Vérifier l'échec** — le test échoue (le téléchargement est appelé).

- [ ] **Step 3: Implémenter**

`CatalogUpdater.swift` :
1. **Reprise du build sans re-téléchargement** — dans le pipeline de `start()`, avant l'appel `download` :

```swift
                // A complete gz survives a failed build (the .part flow only
                // covers interrupted downloads): reuse it instead of paying
                // the gigabyte again. A finished build deletes it either way.
                if !FileManager.default.fileExists(atPath: cache.path) {
                    try await download(CatalogBuilder.catalogURL, cache) { ... }
                }
```

(déplacer l'appel existant dans le `if`, inchangé par ailleurs.)
2. **Finding parqué de la phase 5** — le `guard let self` du Task doit relâcher la garde process-wide :

```swift
        task = Task { [weak self] in
            guard let self else {
                // The updater died between start() and this first tick: the
                // process-wide guard must not stay latched forever.
                Self.inFlight = false
                return
            }
```

3. **Garde NaN** — dans la vue (`NutritionSettingsView`), la `ProgressView` du téléchargement :

```swift
                        ProgressView(
                            value: total.flatMap { $0 > 0 ? min(megabytes / $0, 1) : nil } ?? 0
                        )
```

`CatalogBuilder.swift` — annulation atteignable jusqu'au bout : après le `COMMIT` final (`if batchOpen { try db.execute("COMMIT") }`), avant l'insert FTS :

```swift
        // The FTS rebuild is one multi-second statement: the last chance to
        // honour « Annuler » is right before it.
        try Task.checkCancellation()
```

`FileDownloader.swift` — supprimer le `do { … } catch { throw error }` inutile autour de `transport.fetch` (appel direct).

`WeightStats.swift` — `window` compare des `DateKey` (Comparable) plutôt que leurs `raw` :

```swift
        return weights.filter { $0.dateKey >= cutoff }
```

- [ ] **Step 4: Vérifier le succès** — `CatalogUpdaterTests`, `WeightStatsTests`, `FileDownloaderTests`, puis suite complète.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/ Tests/CatalogUpdaterTests.swift
git commit -m "fix(catalogue): reprise du build sans re-téléchargement et gardes restantes"
```

---

### Task 3: NutritionSidePanelModel — le panneau stats en pur

**Files:**
- Create: `Cairn/Features/Nutrition/NutritionSidePanelModel.swift`
- Test: `Tests/NutritionSidePanelModelTests.swift`

**Interfaces:**
- Consumes: `FoodEntry`, `WeightEntry`, `Macros`, `WeightStats` (`delta`, `ratePerWeek`, `weeksToGoal`, `loggingStreak`), `DateKey`.
- Produces (utilisé par Task 4) :

```swift
struct NutritionSidePanelModel: Equatable {
    var averageKcal7d: Int
    var averageProtein7d: Int
    var loggedThisMonth: Int
    var daysElapsedThisMonth: Int
    var streak: Int
    var lastWeightKg: Double?
    var weightDelta7d: Double?
    var weightRatePerWeek: Double?
    var weeksToGoal: Double?
    /// Every day that has at least one entry — the calendar's dots.
    var loggedDays: Set<String>

    @MainActor static func compute(
        entries: [FoodEntry], weights: [WeightEntry],
        goalKg: Double, day: DateKey
    ) -> NutritionSidePanelModel
}
```

Sémantique (portée de `tui/stats_panel.py:stats_lines`) : moyennes sur les **jours enregistrés** de la fenêtre `[day-6, day]` (un jour vide ne dilue pas la moyenne) ; `loggedThisMonth` = jours enregistrés entre le 1er du mois de `day` et `day` inclus ; `daysElapsedThisMonth` = quantième de `day` ; `streak` = `WeightStats.loggingStreak` sur l'ensemble des jours enregistrés, finissant à `day` ; stats de poids sur la liste complète triée.

- [ ] **Step 1: Tests qui échouent**

```swift
// Tests/NutritionSidePanelModelTests.swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionSidePanelModel")
@MainActor
struct NutritionSidePanelModelTests {
    private func entry(_ raw: String, kcal: Double, protein: Double) -> FoodEntry {
        FoodEntry(
            dateKey: DateKey(raw: raw)!, mealSlot: nil, foodName: "x",
            kcal100: kcal, protein100: protein, carbs100: 0, fat100: 0,
            grams: 100, sortOrder: 0
        )
    }

    private func weight(_ raw: String, _ kg: Double) -> WeightEntry {
        WeightEntry(dateKey: DateKey(raw: raw)!, weightKg: kg)
    }

    @Test("les moyennes 7 j ne comptent que les jours enregistrés")
    func averagesIgnoreEmptyDays() throws {
        // Deux jours enregistrés dans la fenêtre : (2000+100) kcal et 1000 kcal.
        let entries = [
            entry("2026-08-08", kcal: 2000, protein: 100),
            entry("2026-08-08", kcal: 100, protein: 10),
            entry("2026-08-05", kcal: 1000, protein: 50),
            // Hors fenêtre de 7 jours (day-6 = 02/08).
            entry("2026-08-01", kcal: 9000, protein: 900),
        ]
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: [], goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.averageKcal7d == (2100 + 1000) / 2)
        #expect(model.averageProtein7d == (110 + 50) / 2)
    }

    @Test("régularité du mois et série")
    func monthRegularityAndStreak() throws {
        let entries = [
            entry("2026-08-06", kcal: 1, protein: 1),
            entry("2026-08-07", kcal: 1, protein: 1),
            entry("2026-08-08", kcal: 1, protein: 1),
            entry("2026-07-31", kcal: 1, protein: 1),  // mois précédent
        ]
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: [], goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.loggedThisMonth == 3)
        #expect(model.daysElapsedThisMonth == 8)
        #expect(model.streak == 3)
        #expect(model.loggedDays.contains("2026-07-31"))
    }

    @Test("la série s'arrête au premier trou")
    func streakStopsAtGap() throws {
        let entries = [
            entry("2026-08-08", kcal: 1, protein: 1),
            entry("2026-08-06", kcal: 1, protein: 1),  // trou le 07
        ]
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: [], goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.streak == 1)
    }

    @Test("le volet poids reprend les stats de WeightStats")
    func weightSection() throws {
        let weights = [
            weight("2026-07-25", 74.0), weight("2026-08-01", 73.5),
            weight("2026-08-08", 73.0),
        ]
        let model = NutritionSidePanelModel.compute(
            entries: [], weights: weights, goalKg: 70,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.lastWeightKg == 73.0)
        #expect(model.weightDelta7d == -0.5)
        #expect(model.weightRatePerWeek != nil)
        #expect(model.weeksToGoal != nil)
        #expect(model.averageKcal7d == 0)
    }

    @Test("tout vide : zéros et nils, pas de crash")
    func emptyInputs() throws {
        let model = NutritionSidePanelModel.compute(
            entries: [], weights: [], goalKg: 0,
            day: DateKey(raw: "2026-08-08")!
        )
        #expect(model.averageKcal7d == 0)
        #expect(model.streak == 0)
        #expect(model.lastWeightKg == nil)
        #expect(model.weeksToGoal == nil)
    }
}
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/NutritionSidePanelModel.swift
import Foundation
import SwiftData

/// Everything the detail-column side panel shows, in one pure pass — the
/// port of suivinut's `stats_panel.stats_lines`, minus the markup.
struct NutritionSidePanelModel: Equatable {
    var averageKcal7d: Int
    var averageProtein7d: Int
    var loggedThisMonth: Int
    var daysElapsedThisMonth: Int
    var streak: Int
    var lastWeightKg: Double?
    var weightDelta7d: Double?
    var weightRatePerWeek: Double?
    var weeksToGoal: Double?
    var loggedDays: Set<String>

    @MainActor
    static func compute(
        entries: [FoodEntry], weights: [WeightEntry],
        goalKg: Double, day: DateKey
    ) -> NutritionSidePanelModel {
        // Averages over the *logged* days of the trailing week: an empty day
        // is a day off the journal, not a zero that drags the mean down.
        let windowStart = day.advanced(by: -6)
        var totalsByDay: [String: Macros] = [:]
        var loggedDays: Set<String> = []
        for entry in entries {
            loggedDays.insert(entry.dateKeyRaw)
            if entry.dateKeyRaw >= windowStart.raw, entry.dateKeyRaw <= day.raw {
                totalsByDay[entry.dateKeyRaw, default: .zero] =
                    totalsByDay[entry.dateKeyRaw, default: .zero] + Macros(of: entry)
            }
        }
        let dayTotals = Array(totalsByDay.values)
        let loggedCount = dayTotals.count
        let averageKcal = loggedCount == 0
            ? 0
            : Int((dayTotals.map(\.kcal).reduce(0, +) / Double(loggedCount)).rounded())
        let averageProtein = loggedCount == 0
            ? 0
            : Int((dayTotals.map(\.protein).reduce(0, +) / Double(loggedCount)).rounded())

        let monthStart = String(day.raw.prefix(8)) + "01"
        let loggedThisMonth = loggedDays
            .filter { $0 >= monthStart && $0 <= day.raw }.count
        let daysElapsed = Int(day.raw.suffix(2)) ?? 0

        let points = weights
            .compactMap { entry in
                entry.dateKey.map {
                    WeightPoint(dateKey: $0, weightKg: entry.weightKg)
                }
            }
            .sorted { $0.dateKey < $1.dateKey }

        return NutritionSidePanelModel(
            averageKcal7d: averageKcal,
            averageProtein7d: averageProtein,
            loggedThisMonth: loggedThisMonth,
            daysElapsedThisMonth: daysElapsed,
            streak: WeightStats.loggingStreak(loggedDates: loggedDays, endingAt: day),
            lastWeightKg: points.last?.weightKg,
            weightDelta7d: WeightStats.delta(points),
            weightRatePerWeek: WeightStats.ratePerWeek(points),
            weeksToGoal: goalKg > 0
                ? WeightStats.weeksToGoal(points, goal: goalKg) : nil,
            loggedDays: loggedDays
        )
    }
}
```

- [ ] **Step 4: Vérifier le succès** — la suite, 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionSidePanelModel.swift Tests/NutritionSidePanelModelTests.swift
git commit -m "feat(alimentation): modèle pur du panneau stats latéral"
```

---

### Task 4: Mini-calendrier et colonne détail

**Files:**
- Create: `Cairn/Features/Nutrition/MiniCalendarModel.swift`, `Cairn/Features/Nutrition/MiniCalendarView.swift`, `Cairn/Features/Nutrition/NutritionSidePanel.swift`
- Modify: `Cairn/App/RootView.swift` (état `nutritionDateKey` + colonne détail), `Cairn/Features/Nutrition/NutritionDayView.swift` (`dateKey` devient un binding + Échap → aujourd'hui)
- Test: `Tests/MiniCalendarModelTests.swift`

**Interfaces:**
- Consumes: `NutritionSidePanelModel` (Task 3), `DateKey`, `Format`.
- Produces : `NutritionSidePanel(selected: Binding<DateKey>)` ; `NutritionDayView(dateKey: Binding<DateKey>, onCommand:)` ; `MiniCalendarModel.weeks(containing:calendar:) -> [[DateKey?]]`.

- [ ] **Step 1: La grille pure et ses tests**

```swift
// Cairn/Features/Nutrition/MiniCalendarModel.swift
import Foundation

/// The month grid: Monday-first weeks, nil-padded at both ends — pure so
/// the week math is testable without a view.
enum MiniCalendarModel {
    static func weeks(
        containing day: DateKey, calendar: Calendar = .current
    ) -> [[DateKey?]] {
        var calendar = calendar
        calendar.firstWeekday = 2  // Monday, like every date in this app.
        let anchor = day.date(calendar: calendar)
        guard let interval = calendar.dateInterval(of: .month, for: anchor)
        else { return [] }
        let first = DateKey(interval.start, calendar: calendar)
        let dayCount = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
        // Weekday of the 1st, expressed Monday=0 … Sunday=6.
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [DateKey?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(first.advanced(by: offset, calendar: calendar))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }
}
```

```swift
// Tests/MiniCalendarModelTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("MiniCalendarModel")
struct MiniCalendarModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    @Test("août 2026 : samedi 1er, lundi en tête, 31 jours")
    func august2026() throws {
        let weeks = MiniCalendarModel.weeks(
            containing: DateKey(raw: "2026-08-08")!, calendar: calendar
        )
        // Le 1er août 2026 est un samedi : 5 cases vides devant.
        #expect(weeks[0].prefix(5).allSatisfy { $0 == nil })
        #expect(weeks[0][5]?.raw == "2026-08-01")
        #expect(weeks[0][6]?.raw == "2026-08-02")
        // Toutes les semaines font 7 cases, et on retrouve les 31 jours.
        #expect(weeks.allSatisfy { $0.count == 7 })
        let days = weeks.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
        #expect(days.first?.raw == "2026-08-01")
        #expect(days.last?.raw == "2026-08-31")
    }

    @Test("un mois commençant un lundi n'a pas de cases vides devant")
    func mondayStartHasNoLeadingGap() throws {
        // Juin 2026 commence un lundi.
        let weeks = MiniCalendarModel.weeks(
            containing: DateKey(raw: "2026-06-15")!, calendar: calendar
        )
        #expect(weeks[0][0]?.raw == "2026-06-01")
    }
}
```

RED (compilation) puis GREEN sur `-only-testing:CairnTests/MiniCalendarModelTests`.

- [ ] **Step 2: La vue calendrier**

```swift
// Cairn/Features/Nutrition/MiniCalendarView.swift
import SwiftUI

/// suivinut's mini calendar: dots on logged days, click to travel. The
/// displayed month follows the selection but can be browsed independently.
struct MiniCalendarView: View {
    @Binding var selected: DateKey
    let loggedDays: Set<String>

    /// A day of the displayed month — kept as state so browsing months does
    /// not move the selection until a day is clicked.
    @State private var shownMonth: DateKey

    init(selected: Binding<DateKey>, loggedDays: Set<String>) {
        _selected = selected
        self.loggedDays = loggedDays
        _shownMonth = State(initialValue: selected.wrappedValue)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    shownMonth = shownMonth.monthStart.advanced(by: -1).monthStart
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(Self.monthFormatter.string(from: shownMonth.date()).capitalized)
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    shownMonth = shownMonth.monthEnd().advanced(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.borderless)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) {
                        Text(["L", "M", "M", "J", "V", "S", "D"][$0])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(
                    Array(MiniCalendarModel.weeks(containing: shownMonth).enumerated()),
                    id: \.offset
                ) { _, week in
                    GridRow {
                        ForEach(week.indices, id: \.self) { index in
                            dayCell(week[index])
                        }
                    }
                }
            }
        }
        .onChange(of: selected) { _, newValue in shownMonth = newValue }
    }

    @ViewBuilder
    private func dayCell(_ day: DateKey?) -> some View {
        if let day {
            Button {
                selected = day
            } label: {
                VStack(spacing: 1) {
                    Text(String(Int(day.raw.suffix(2)) ?? 0))
                        .font(.caption.monospacedDigit())
                    Circle()
                        .fill(loggedDays.contains(day.raw)
                              ? Color.accentColor : .clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(
                    day == selected
                        ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 4)
                )
            }
            .buttonStyle(.borderless)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 24)
        }
    }
}
```

et les deux aides de mois dans `Cairn/Model/DateKey.swift` :

```swift
    /// First day of this key's month.
    var monthStart: DateKey {
        DateKey(raw: String(raw.prefix(8)) + "01")!
    }

    /// Last day of this key's month.
    func monthEnd(calendar: Calendar = .current) -> DateKey {
        let start = monthStart
        let count = calendar.range(
            of: .day, in: .month, for: start.date(calendar: calendar)
        )?.count ?? 28
        return start.advanced(by: count - 1, calendar: calendar)
    }
```

(les chevrons du listing utilisent déjà ces deux aides : mois précédent = `monthStart.advanced(by: -1).monthStart`, mois suivant = `monthEnd().advanced(by: 1)` — exacts sur les mois de 28 à 31 jours.)

- [ ] **Step 3: Le panneau latéral**

```swift
// Cairn/Features/Nutrition/NutritionSidePanel.swift
import SwiftUI
import SwiftData

/// The detail column beside the journal screens: suivinut's side panel —
/// mini calendar on top, the 7-day / weight / regularity stats below.
struct NutritionSidePanel: View {
    @Binding var selected: DateKey

    @Query private var entries: [FoodEntry]
    @Query(sort: \WeightEntry.dateKeyRaw) private var weights: [WeightEntry]
    @AppStorage(NutritionSettings.weightGoalKey)
    private var weightGoal = NutritionSettings.defaultWeightGoalKg

    var body: some View {
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: weights,
            goalKg: weightGoal, day: selected
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MiniCalendarView(selected: $selected, loggedDays: model.loggedDays)
                Divider()
                section("Apports · 7 j") {
                    statLine("moy. \(model.averageKcal7d) kcal/j")
                    statLine("moy. \(model.averageProtein7d) g P/j")
                }
                section("Poids") {
                    if let last = model.lastWeightKg {
                        statLine(
                            "\(Format.typedNumber(last)) kg · obj "
                            + "\(Format.typedNumber(weightGoal))"
                        )
                        if let delta = model.weightDelta7d {
                            coloredLine(
                                "vs il y a 7 j : \(Format.signedTwoDecimals(delta)) kg",
                                favorable: delta <= 0
                            )
                        }
                        if let rate = model.weightRatePerWeek {
                            coloredLine(
                                "\(Format.signedTwoDecimals(rate)) kg/sem",
                                favorable: rate <= 0
                            )
                        }
                        if let weeks = model.weeksToGoal {
                            statLine("→ obj : ~\(Int(weeks.rounded())) sem")
                        }
                    } else {
                        statLine("aucune pesée")
                    }
                }
                section("Régularité") {
                    statLine(
                        "\(model.loggedThisMonth)/\(model.daysElapsedThisMonth) j ce mois"
                    )
                    statLine("série \(model.streak) j")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            content()
        }
    }

    private func statLine(_ text: String) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    /// Green when the trend serves the goal, red otherwise — the one colour
    /// rule suivinut's panel uses.
    private func coloredLine(_ text: String, favorable: Bool) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(favorable ? .green : .red)
    }
}
```

**Note :** `Format.signedTwoDecimals` est créé en Task 6 — pour garder cette task compilable seule, l'implémenter ICI (Task 6 ne fera que l'adopter côté Poids) :

```swift
// Cairn/Features/Shared/Formatters.swift — à côté de typedNumber
    private static let signedTwoDecimalsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        // U+2212, the real minus — a hyphen reads as a dash in running text.
        formatter.negativePrefix = "−"
        return formatter
    }()

    /// Signed rates and deltas: two decimals so −0,04 kg/sem never rounds
    /// to the lie « −0,0 ».
    static func signedTwoDecimals(_ value: Double) -> String {
        signedTwoDecimalsFormatter.string(from: value as NSNumber) ?? "\(value)"
    }
```

- [ ] **Step 4: RootView et le binding du jour**

`RootView.swift` :
1. État : `@State private var nutritionDateKey = DateKey(Date())`.
2. Branche de contenu : `NutritionDayView(dateKey: $nutritionDateKey, onCommand: performInNutrition)`.
3. `detailColumn` — première branche AVANT `if let selected` :

```swift
        if showsNutrition || showsWeight {
            // The journal screens claim the pane: the side panel replaces
            // whatever activity was left selected behind them.
            NutritionSidePanel(selected: $nutritionDateKey)
                .frame(minWidth: Self.detailMinWidth)
        } else if let selected {
```

`NutritionDayView.swift` :
1. `@State private var dateKey = DateKey(Date())` devient `@Binding var dateKey: DateKey` (paramètre d'init, avant `onCommand` — ordre : `init(dateKey:onCommand:)`).
2. Échap ramène à aujourd'hui (esprit suivinut) — dans la fermeture `vimKeys` de la Task 1, avant le `default:` :

```swift
            case .clear:
                // Escape peels the date first: coming back to today is the
                // journal's own « clear », the window's comes after.
                if dateKey != DateKey(Date()) {
                    dateKey = DateKey(Date())
                    return true
                }
                return onCommand(command)
```

- [ ] **Step 5: Builder + suite complète** — build OK, tout vert.

- [ ] **Step 6: Commit**

```bash
git add Cairn/Features/Nutrition/ Cairn/Features/Shared/Formatters.swift Cairn/Model/DateKey.swift Cairn/App/RootView.swift Tests/MiniCalendarModelTests.swift
git commit -m "feat(alimentation): mini-calendrier et panneau stats dans la colonne détail"
```

---

### Task 5: Drag de réordonnancement des aliments

**Files:**
- Modify: `Cairn/Features/Nutrition/NutritionJournal.swift` (+ `placeEntry`)
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift` (draggable/dropDestination)
- Test: `Tests/NutritionJournalTests.swift` (ajouts)

**Interfaces:**
- Produces :

```swift
extension NutritionJournal {
    /// Re-seats `entry` right after `target` in their shared (day, meal),
    /// renumbering the whole meal 0..n — suivinut's `place_entry_after`.
    /// No-op when the two live in different meals or days.
    @MainActor static func placeEntry(
        _ entry: FoodEntry, after target: FoodEntry, in context: ModelContext
    ) throws
}
```

- [ ] **Step 1: Tests qui échouent** (ajouts dans `NutritionJournalTests`)

```swift
    @Test("placer après renumérote tout le repas")
    func placeAfterRenumbers() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let a = try addFood("A", to: slot, context: context)
        let b = try addFood("B", to: slot, context: context)
        let c = try addFood("C", to: slot, context: context)

        // A après C : ordre B, C, A — et des sort_order 0,1,2 propres.
        try NutritionJournal.placeEntry(a, after: c, in: context)
        let ordered = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.foodName) == ["B", "C", "A"])
        #expect(ordered.map(\.sortOrder) == [0, 1, 2])

        // C après A : B, A, C.
        try NutritionJournal.placeEntry(c, after: a, in: context)
        let again = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(again.map(\.foodName) == ["B", "A", "C"])
    }

    @Test("placer après une cible d'un autre repas est sans effet")
    func placeAcrossMealsIsNoOp() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let a = try addFood("A", to: breakfast, context: context)
        let d = try addFood("D", to: dinner, context: context)

        let before = (a.sortOrder, a.mealSlot?.name)
        try NutritionJournal.placeEntry(a, after: d, in: context)
        #expect((a.sortOrder, a.mealSlot?.name) == before)
    }
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter la mutation**

```swift
extension NutritionJournal {
    @MainActor
    static func placeEntry(
        _ entry: FoodEntry, after target: FoodEntry, in context: ModelContext
    ) throws {
        guard let slot = entry.mealSlot,
              target.mealSlot?.persistentModelID == slot.persistentModelID,
              target.dateKeyRaw == entry.dateKeyRaw,
              target.persistentModelID != entry.persistentModelID
        else { return }
        var ordered = try siblings(of: entry.dateKeyRaw, slot: slot, in: context)
            .sorted { $0.sortOrder < $1.sortOrder }
        guard let from = ordered.firstIndex(where: {
            $0.persistentModelID == entry.persistentModelID
        }) else { return }
        let moved = ordered.remove(at: from)
        guard let to = ordered.firstIndex(where: {
            $0.persistentModelID == target.persistentModelID
        }) else { return }
        ordered.insert(moved, at: to + 1)
        // Renumber the whole meal: gaps accumulated by drags would otherwise
        // grow unbounded, and a clean 0..n is what suivinut writes too.
        for (position, sibling) in ordered.enumerated() {
            sibling.sortOrder = position
        }
        try context.save()
    }
}
```

- [ ] **Step 4: Le drag dans la vue**

`NutritionDayView.swift` :

1. Le type transféré, en haut du fichier (hors struct) :

```swift
/// What a dragged food row carries: just enough to find the entry again.
/// `PersistentIdentifier` is Codable, so the payload stays tiny and honest.
struct FoodEntryDragPayload: Codable, Transferable {
    let id: PersistentIdentifier

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
```

(+ `import UniformTypeIdentifiers` en tête de fichier.)

2. Sur chaque `GridRow` d'aliment (après le `.contextMenu`) :

```swift
                        .draggable(FoodEntryDragPayload(id: row.entryID))
                        .dropDestination(for: FoodEntryDragPayload.self) {
                            payloads, _ in
                            guard let payload = payloads.first else {
                                return false
                            }
                            return drop(payload.id, onto: row.entryID)
                        }
```

3. L'aide :

```swift
    /// Reorders by drag: the dragged entry lands right after the row it was
    /// dropped on. Same-meal only — `placeEntry` refuses the rest, and
    /// returning false lets the system animate the rejection.
    private func drop(
        _ draggedID: PersistentIdentifier, onto targetID: PersistentIdentifier
    ) -> Bool {
        guard draggedID != targetID,
              let dragged = entry(for: draggedID),
              let target = entry(for: targetID)
        else { return false }
        guard dragged.mealSlot?.persistentModelID
            == target.mealSlot?.persistentModelID
        else { return false }
        do {
            try NutritionJournal.placeEntry(dragged, after: target, in: modelContext)
            return true
        } catch {
            writeFailureMessage =
                "Le déplacement n'a pas pu être enregistré. \(error.localizedDescription)"
            return false
        }
    }
```

- [ ] **Step 5: Builder + suite complète** — build OK, tout vert.

- [ ] **Step 6: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionJournal.swift Cairn/Features/Nutrition/NutritionDayView.swift Tests/NutritionJournalTests.swift
git commit -m "feat(alimentation): réordonnancement des aliments par glisser-déposer"
```

---

### Task 6: Finitions restantes

**Files:**
- Modify: `Cairn/Features/Nutrition/WeightView.swift` (formatteur signé)
- Modify: `Cairn/Features/Nutrition/FoodPickerView.swift` (message d'erreur de recherche)
- Modify: `Cairn/Features/Nutrition/NutritionJournal.swift` (`applyRecipe` en une sauvegarde)
- Create: `Cairn/Features/Nutrition/SuivinutImportFlow.swift` ; Modify: `Cairn/Features/Nutrition/NutritionDayView.swift`, `Cairn/Features/Nutrition/NutritionSettingsView.swift` (déduplication)
- Modify: `docs/specs/2026-08-08-alimentation-design.md` (§8)
- Test: `Tests/FormattersTests.swift`, `Tests/NutritionJournalTests.swift` (ajouts)

- [ ] **Step 1: Tests qui échouent**

```swift
    // FormattersTests
    @Test("le format signé garde deux décimales et le vrai moins")
    func signedTwoDecimals() {
        #expect(Format.signedTwoDecimals(-0.04) == "−0,04")
        #expect(Format.signedTwoDecimals(0.4) == "+0,4")
        #expect(Format.signedTwoDecimals(-1.25) == "−1,25")
        #expect(Format.signedTwoDecimals(0) == "+0,0")
    }
```

```swift
    // NutritionJournalTests
    @Test("appliquer une recette n'écrit qu'une fois")
    func applyRecipeSavesOnce() throws {
        // Pas d'espion de save() : on vérifie l'invariant observable — les
        // sort_order restent contigus et l'ordre est bon, comme avant.
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let recipe = Recipe(name: "R", mealSlot: slot)
        context.insert(recipe)
        for (index, name) in ["Un", "Deux", "Trois"].enumerated() {
            let item = RecipeItem(
                foodName: name, kcal100: 100, protein100: 1,
                carbs100: 1, fat100: 1, grams: 100
            )
            item.sortOrder = index
            item.recipe = recipe
            context.insert(item)
        }
        try context.save()
        try NutritionJournal.applyRecipe(
            recipe, to: DateKey(raw: "2026-08-08")!, slot: slot, in: context
        )
        let ordered = try context.fetch(FetchDescriptor<FoodEntry>())
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.foodName) == ["Un", "Deux", "Trois"])
        #expect(context.hasChanges == false)
    }
```

- [ ] **Step 2: Vérifier l'échec** — `signedTwoDecimals` n'existe que si la Task 4 est passée (sinon compilation) ; le test de recette passe déjà si `applyRecipe` est correct — le durcissement vise le nombre de sauvegardes, l'assertion `hasChanges == false` reste vraie avant/après : ce test est un filet de non-régression, pas un RED strict. L'accepter tel quel.

- [ ] **Step 3: Implémenter**

1. **`WeightView.swift`** — remplacer l'aide `signed(_:)` par le formatteur partagé :

```swift
    private func signed(_ value: Double) -> String {
        Format.signedTwoDecimals(value)
    }
```

2. **`FoodPickerView.swift`** — la recherche en échec parle (spec §9) : état `@State private var searchErrorMessage: String?` ; dans `runSearch` :

```swift
        do {
            results = try catalog.search(text)
            searchErrorMessage = nil
        } catch {
            // A broken catalog must say so — a silently empty list reads as
            // « no result », which is a different fact.
            results = []
            searchErrorMessage =
                "La recherche a échoué : \(error.localizedDescription)"
        }
```

et dans `searchPane`, sous la `List` :

```swift
                if let searchErrorMessage {
                    Text(searchErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
```

3. **`NutritionJournal.applyRecipe`** — une seule sauvegarde :

```swift
    @MainActor
    static func applyRecipe(
        _ recipe: Recipe, to dateKey: DateKey, slot: MealSlot,
        in context: ModelContext
    ) throws {
        // One save for the whole recipe: a mid-apply failure must not leave
        // half a porridge in the journal.
        var next = (try siblings(of: dateKey.raw, slot: slot, in: context)
            .map(\.sortOrder).max() ?? 0) + 1
        for item in recipe.orderedItems {
            context.insert(FoodEntry(
                dateKey: dateKey, mealSlot: slot, foodName: item.foodName,
                kcal100: item.kcal100, protein100: item.protein100,
                carbs100: item.carbs100, fat100: item.fat100,
                grams: item.grams, sortOrder: next,
                productCode: item.productCode
            ))
            next += 1
        }
        try context.save()
    }
```

4. **`SuivinutImportFlow.swift`** — le flux d'import unique, extrait des deux vues :

```swift
// Cairn/Features/Nutrition/SuivinutImportFlow.swift
import SwiftUI
import SwiftData
import AppKit

/// The one import flow both entry points share (onboarding banner and the
/// settings tab): pick the journal, import on a context of its own, apply
/// the journal's targets, copy the sibling catalog. Returns the message the
/// caller shows in its alert.
@MainActor
enum SuivinutImportFlow {
    static func chooseAndImport(container: ModelContainer) -> String? {
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
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return importJournal(from: url, container: container)
    }

    static func importJournal(
        from url: URL, container: ModelContainer
    ) -> String {
        // A context of its own: `run` rolls back on failure, and rolling
        // back a shared context would discard unrelated pending edits. The
        // cross-context @Query refresh was verified live in phase 3.
        let importContext = ModelContext(container)
        do {
            let summary = try SuivinutImporter(context: importContext)
                .run(journalPath: url.path)
            let defaults = UserDefaults.standard
            if let value = summary.proteinTargetG {
                defaults.set(value, forKey: NutritionSettings.proteinTargetKey)
            }
            if let value = summary.fatTargetG {
                defaults.set(value, forKey: NutritionSettings.fatTargetKey)
            }
            if let value = summary.weightGoalKg {
                defaults.set(value, forKey: NutritionSettings.weightGoalKey)
            }
            _ = try? SuivinutImporter.copyCatalog(
                nextTo: url,
                to: URL.applicationSupportDirectory.appending(path: "Cairn")
            )
            return "\(summary.entries) aliments, \(summary.weights) pesées et "
                + "\(summary.recipes) recettes importés."
        } catch {
            return "L'import a échoué : \(error.localizedDescription) "
                + "Rien n'a été modifié."
        }
    }
}
```

Dans `NutritionDayView` et `NutritionSettingsView` : supprimer leurs `chooseAndImport`/`importJournal` locaux et appeler :

```swift
        importMessage = SuivinutImportFlow.chooseAndImport(
            container: modelContext.container
        )
```

(le `seed()` de l'onboarding ne bouge pas ; l'écriture des cibles passe par `UserDefaults` avec les mêmes clés que les `@AppStorage` — même stockage, mêmes vues rafraîchies).

5. **`RecipesManagerSheet.swift`** — l'échec d'ajout d'item était invisible (l'`errorMessage` du parent est occulté par la sheet enfant) : déplacer l'affichage de l'erreur d'ajout DANS `addItemSheet` (un `@State private var addItemErrorMessage: String?` propre à ce chemin, affiché sous le `FoodPickerView`, remis à nil à chaque présentation), et remettre `errorMessage` du parent à nil quand une action ultérieure réussit.

6. **Spec** — `docs/specs/2026-08-08-alimentation-design.md` §8 : remplacer « éditeur de **jours-types** (nom + kcal, ajout/suppression/réordonnancement) » par « éditeur de **jours-types** (nom + kcal, ajout/suppression — le réordonnancement a été retiré : l'ordre n'a d'effet visible nulle part, les menus trient par kcal) ».

- [ ] **Step 4: Builder + suite complète** — build OK, tout vert.

- [ ] **Step 5: Vérification visuelle de la phase**

En mode démo : `gn`/`gp`/`a`/`w`/`?` (aide à jour) ; colonne détail (calendrier navigable, points sur les jours remplis, clic = navigation, stats cohérentes, plus de volet d'activité résiduel) ; Échap revient à aujourd'hui ; drag d'un aliment dans son repas (et refus propre entre repas) ; tuiles Poids en « −0,04 » ; import depuis l'onboarding ET les Réglages.

- [ ] **Step 6: Commit**

```bash
git add Cairn/Features/Nutrition/ Cairn/Features/Shared/Formatters.swift docs/specs/2026-08-08-alimentation-design.md Tests/FormattersTests.swift Tests/NutritionJournalTests.swift
git commit -m "fix(alimentation): finitions de fin de spec (formats, recherche, import unifié)"
```

---

## Après cette phase

La spec est close. Resteront hors périmètre, comme décidé en brainstorming : undo/redo spécifique, sync retour vers `journal.db`, code-barres, portions, micro-nutriments. Candidats si l'usage en donne envie : confirmation avant d'écraser une pesée en déplaçant sa date, débounce de recherche, `fetchCount` pour la porte d'import.
