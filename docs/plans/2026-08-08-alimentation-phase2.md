# Alimentation — Phase 2 : saisie complète

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre le journal éditable : recherche d'aliments dans le catalogue OFF hors ligne, saisie manuelle, grammes, édition, suppression, réordonnancement, et choix du jour-type depuis l'écran.

**Architecture:** La recherche lit le `off.db` copié en phase 1 via `SQLiteDatabase` (étendu avec des bindings) derrière un `FoodCatalog` dédié. Les mutations du journal sont centralisées dans `NutritionJournal` (fonctions pures @MainActor sur le `ModelContext`, sémantique portée de `db/journal.py`). L'UI ajoute deux sheets (ajout, édition) et des actions de ligne, sans ViewModel.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, SQLite3 système (FTS5), Swift Testing. Aucune dépendance externe.

**Spec :** `docs/specs/2026-08-08-alimentation-design.md` (§4 catalogue-lecture, §5 saisie, §9, §11 phase 2). Phase 1 mergée : `DateKey`, modèles, `NutritionMath`, `SQLiteDatabase`, `SuivinutImporter`, `NutritionDayModel`, `NutritionSeed`, `NutritionDayView`.

## Global Constraints

- macOS 15.0 minimum, Swift 6.0, concurrence stricte (`@MainActor` sur tout ce qui touche `ModelContext` ou `SQLiteDatabase` depuis l'UI).
- Aucun gestionnaire de paquets, aucune dépendance externe — FTS5 vient du SQLite système.
- Identifiants, types et commentaires en **anglais** ; chaînes visibles en **français** ; commentaires « pourquoi », jamais « quoi ».
- Chiffres affichés en `monospacedDigit`, couleurs système uniquement.
- Après **tout ajout de fichier source** : `xcodegen generate` avant de builder.
- Tests : Swift Testing (`import Testing`, `@Suite`, `#expect`), noms en français, jamais XCTest.
- Commits : Conventional Commits en français, scope `alimentation`, sujet descriptif.
- Commande de test (adapter la cible) :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/FoodCatalogTests 2>&1 | tail -5
  ```
- Sémantique portée de suivinut **à l'identique** : requête FTS = tokens `"tok"*` joints par espaces (AND implicite), `ORDER BY rank LIMIT 50` ; ajout d'entrée en fin de repas ; déplacement = échange de `sortOrder` avec le voisin du même (date, repas), no-op au bord ; édition = libellé + grammes seulement (macros /100 g inchangées) ; jour-type = upsert sur la date.

---

### Task 1: Bindings SQLite

**Files:**
- Modify: `Cairn/Features/Nutrition/SQLiteDatabase.swift` (méthode `rows`)
- Test: `Tests/SQLiteDatabaseTests.swift` (ajouts)

**Interfaces:**
- Consumes: `SQLiteDatabase` existant (`rows(_ sql: String)`, `Value`, `Error`).
- Produces: `rows(_ sql: String, bindings: [Value] = [])` — les appels existants sans bindings compilent inchangés. Un nombre de bindings différent du nombre de `?` du statement jette `Error`. Task 2 en dépend pour `MATCH ?` et `LIMIT ?`.

- [ ] **Step 1: Écrire les tests qui échouent** (à ajouter dans la suite existante `SQLiteDatabaseTests`)

```swift
    @Test("les bindings passent texte, entier, réel et null")
    func bindsAllValueKinds() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute(
            "CREATE TABLE t (name TEXT, kcal REAL, count INTEGER, note TEXT);"
            + "INSERT INTO t VALUES ('Riz', 350.0, 2, NULL);"
            + "INSERT INTO t VALUES ('Crème', 300.0, 5, 'x');"
        )
        let rows = try db.rows(
            "SELECT name FROM t WHERE kcal = ? AND count = ? AND name = ?",
            bindings: [.real(350.0), .integer(2), .text("Riz")]
        )
        #expect(rows.count == 1)
        #expect(rows[0]["name"] == .text("Riz"))
        let none = try db.rows(
            "SELECT name FROM t WHERE note IS NOT ?", bindings: [.null]
        )
        #expect(none.count == 1)
        #expect(none[0]["name"] == .text("Crème"))
    }

    @Test("un texte piégé reste une valeur, jamais du SQL")
    func bindingsAreNotInterpolated() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute(
            "CREATE TABLE t (name TEXT);"
            + "INSERT INTO t VALUES ('sain');"
        )
        let hostile = "'; DROP TABLE t; --"
        let rows = try db.rows(
            "SELECT name FROM t WHERE name = ?", bindings: [.text(hostile)]
        )
        #expect(rows.isEmpty)
        // La table doit avoir survécu au texte hostile.
        #expect(try db.rows("SELECT name FROM t").count == 1)
    }

    @Test("un nombre de bindings incohérent échoue proprement")
    func mismatchedBindingCountThrows() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE t (a TEXT)")
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try db.rows("SELECT a FROM t WHERE a = ?", bindings: [])
        }
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try db.rows(
                "SELECT a FROM t", bindings: [.text("de trop")]
            )
        }
    }
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/SQLiteDatabaseTests 2>&1 | tail -5`
Expected: échec de compilation (`rows` n'a pas de paramètre `bindings`).

- [ ] **Step 3: Implémenter**

Dans `SQLiteDatabase.swift`, remplacer la signature de `rows` et ajouter la liaison :

```swift
    /// All rows of a SELECT, keyed by column name. Bindings replace `?`
    /// placeholders positionally — user-provided text (a search query) must
    /// never be spliced into SQL. Materialising the whole result is fine for
    /// the volumes this reads.
    func rows(
        _ sql: String, bindings: [Value] = []
    ) throws -> [[String: Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK
        else {
            throw Error(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var result: [[String: Value]] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            var row: [String: Value] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = value(of: statement, at: index)
            }
            result.append(row)
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw Error(message: String(cString: sqlite3_errmsg(handle)))
        }
        return result
    }

    /// `SQLITE_TRANSIENT`: tells SQLite to copy the bytes immediately, so the
    /// Swift string may be freed as soon as the call returns.
    private static let transientDestructor = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self
    )

    private func bind(_ bindings: [Value], to statement: OpaquePointer?) throws {
        let expected = sqlite3_bind_parameter_count(statement)
        guard bindings.count == Int(expected) else {
            throw Error(
                message: "\(bindings.count) valeur(s) pour \(expected) paramètre(s)."
            )
        }
        for (index, value) in bindings.enumerated() {
            let slot = Int32(index + 1)
            let result: Int32
            switch value {
            case let .integer(number):
                result = sqlite3_bind_int64(statement, slot, number)
            case let .real(number):
                result = sqlite3_bind_double(statement, slot, number)
            case let .text(string):
                result = sqlite3_bind_text(
                    statement, slot, string, -1, Self.transientDestructor
                )
            case .null:
                result = sqlite3_bind_null(statement, slot)
            }
            guard result == SQLITE_OK else {
                throw Error(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
```

Note : le corps de boucle avec `stepResult` existe déjà depuis le fix de la revue finale de la phase 1 — ne pas le dupliquer, seulement insérer `try bind(...)` après le `defer` et ajouter le paramètre.

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2 (toute la suite `SQLiteDatabaseTests`, anciens tests compris).
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/SQLiteDatabase.swift Tests/SQLiteDatabaseTests.swift
git commit -m "feat(alimentation): bindings SQLite pour les requêtes paramétrées"
```

---

### Task 2: FoodCatalog — recherche FTS5 dans off.db

**Files:**
- Create: `Cairn/Features/Nutrition/FoodCatalog.swift`
- Test: `Tests/FoodCatalogTests.swift`

**Interfaces:**
- Consumes: `SQLiteDatabase` avec bindings (Task 1).
- Produces (utilisé par Task 5) :

```swift
@MainActor
final class FoodCatalog {
    struct Product: Equatable {
        var code: String
        var name: String
        var brands: String        // "" si NULL
        var kcal100: Double
        var protein100: Double
        var carbs100: Double      // 0 si NULL
        var fat100: Double        // 0 si NULL
        var servingSize: String?
    }
    static var defaultURL: URL   // Application Support/Cairn/off.db
    init(path: String) throws    // lecture seule
    static func openDefault() -> FoodCatalog?  // nil si absent/illisible
    static func ftsQuery(for text: String) -> String?
    func search(_ query: String, limit: Int = 50) throws -> [Product]
}
```

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/FoodCatalogTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("FoodCatalog")
@MainActor
struct FoodCatalogTests {
    /// A miniature off.db with the real schema — the FTS tokenizer options
    /// are the ones that make diacritics-insensitive prefix search work, so
    /// the fixture must use them verbatim.
    private func makeCatalog() throws -> (FoodCatalog, String) {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "off-fixture-\(UUID().uuidString).db").path
        let db = try SQLiteDatabase(path: path)
        try db.execute("""
            CREATE TABLE products (
                code TEXT PRIMARY KEY, name TEXT NOT NULL, brands TEXT,
                quantity TEXT, kcal_100g REAL NOT NULL,
                protein_100g REAL NOT NULL, carbs_100g REAL, fat_100g REAL,
                serving_size TEXT, completeness REAL);
            CREATE VIRTUAL TABLE products_fts USING fts5(
                name, brands, code UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2');
            INSERT INTO products VALUES
                ('1', 'Flocons d''avoine', 'Marque A', NULL,
                 370, 13, 60, 7, '40 g', 0.9),
                ('2', 'Crème fraîche épaisse', 'Laiterie', NULL,
                 300, 2.5, 3, 30, NULL, 0.8),
                ('3', 'Riz basmati', NULL, NULL,
                 350, 7, NULL, NULL, NULL, 0.7),
                ('4', 'Riz complet', 'Marque B', NULL,
                 345, 8, 72, 2.5, NULL, 0.8);
            INSERT INTO products_fts(name, brands, code)
                SELECT name, COALESCE(brands, ''), code FROM products;
            """)
        return (try FoodCatalog(path: path), path)
    }

    @Test("la recherche par préfixe trouve le produit")
    func prefixSearchFinds() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = try catalog.search("floc")
        #expect(results.count == 1)
        #expect(results[0].name == "Flocons d'avoine")
        #expect(results[0].brands == "Marque A")
        #expect(results[0].kcal100 == 370)
        #expect(results[0].servingSize == "40 g")
    }

    @Test("les diacritiques sont ignorés dans les deux sens")
    func diacriticsInsensitive() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.search("creme").count == 1)
        #expect(try catalog.search("crème").count == 1)
        #expect(try catalog.search("epaisse").count == 1)
    }

    @Test("plusieurs mots = ET implicite")
    func multiTokenIsAnd() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.search("flocons avoine").count == 1)
        #expect(try catalog.search("flocons riz").isEmpty)
    }

    @Test("une requête vide ou sans token rend une liste vide sans erreur")
    func emptyQueryYieldsNothing() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.search("").isEmpty)
        #expect(try catalog.search("  !! ").isEmpty)
    }

    @Test("les macros NULL du catalogue deviennent 0, brands vide")
    func nullMacrosCoalesceToZero() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let rice = try catalog.search("basmati")[0]
        #expect(rice.carbs100 == 0)
        #expect(rice.fat100 == 0)
        #expect(rice.brands == "")
        #expect(rice.servingSize == nil)
    }

    @Test("limit borne le nombre de résultats")
    func limitApplies() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let all = try catalog.search("riz")
        #expect(all.count == 2)
        #expect(try catalog.search("riz", limit: 1).count == 1)
    }

    @Test("le constructeur de requête FTS met chaque token en préfixe cité", arguments: [
        ("crème fraîche 30%", "\"crème\"* \"fraîche\"* \"30\"*"),
        ("floc", "\"floc\"*"),
        ("  ", nil),
        ("!!", nil),
    ])
    func ftsQueryBuilder(input: String, expected: String?) {
        #expect(FoodCatalog.ftsQuery(for: input) == expected)
    }

    @Test("openDefault rend nil quand le fichier n'existe pas")
    func openDefaultNilWhenMissing() {
        // defaultURL pointe sur Application Support/Cairn/off.db ; ce test ne
        // doit pas dépendre de l'état de la machine, donc on teste le
        // constructeur direct sur un chemin garanti absent.
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "nope-\(UUID().uuidString)/off.db").path
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try FoodCatalog(path: missing)
        }
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/FoodCatalogTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/FoodCatalog.swift
import Foundation

/// Read-only access to the Open Food Facts catalog (`off.db`), the same
/// SQLite FTS5 file suivinut builds. Kept outside SwiftData on purpose:
/// 180k products and diacritics-insensitive prefix search are FTS5's
/// terrain. Ported from suivinut's `db/catalog.py:search`.
@MainActor
final class FoodCatalog {
    struct Product: Equatable {
        var code: String
        var name: String
        var brands: String
        var kcal100: Double
        var protein100: Double
        var carbs100: Double
        var fat100: Double
        var servingSize: String?
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Cairn/off.db")
    }

    private let db: SQLiteDatabase

    init(path: String) throws {
        db = try SQLiteDatabase(path: path, readOnly: true)
    }

    /// nil when there is no catalog yet — a normal state (phase 5 downloads
    /// one); the UI degrades to manual entry, never crashes.
    static func openDefault() -> FoodCatalog? {
        guard FileManager.default.fileExists(atPath: defaultURL.path) else {
            return nil
        }
        return try? FoodCatalog(path: defaultURL.path)
    }

    /// One quoted prefix term per token, implicit AND between them —
    /// suivinut's `_fts_query`. Tokens are runs of letters, digits or
    /// underscore, so the quotes can never be escaped by the input.
    static func ftsQuery(for text: String) -> String? {
        let tokens = text.split { character in
            !(character.isLetter || character.isNumber || character == "_")
        }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    func search(_ query: String, limit: Int = 50) throws -> [Product] {
        guard let match = Self.ftsQuery(for: query) else { return [] }
        let rows = try db.rows(
            """
            SELECT p.* FROM products_fts f JOIN products p ON p.code = f.code
            WHERE products_fts MATCH ? ORDER BY rank LIMIT ?
            """,
            bindings: [.text(match), .integer(Int64(limit))]
        )
        return rows.map { row in
            Product(
                code: row["code"]?.stringValue ?? "",
                name: row["name"]?.stringValue ?? "",
                brands: row["brands"]?.stringValue ?? "",
                kcal100: row["kcal_100g"]?.doubleValue ?? 0,
                protein100: row["protein_100g"]?.doubleValue ?? 0,
                // NULL in the catalog (incomplete product): 0 is the honest
                // journal value — the entry stores what we know.
                carbs100: row["carbs_100g"]?.doubleValue ?? 0,
                fat100: row["fat_100g"]?.doubleValue ?? 0,
                servingSize: row["serving_size"]?.stringValue
            )
        }
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS (11 cas, paramétrés compris).

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/FoodCatalog.swift Tests/FoodCatalogTests.swift
git commit -m "feat(alimentation): recherche FTS5 dans le catalogue off.db"
```

---

### Task 3: NutritionJournal — mutations du journal

**Files:**
- Create: `Cairn/Features/Nutrition/NutritionJournal.swift`
- Test: `Tests/NutritionJournalTests.swift`

**Interfaces:**
- Consumes: modèles phase 1 (`FoodEntry`, `MealSlot`, `NutritionDay`, `DayType`), `DateKey`.
- Produces (utilisé par Tasks 5-6) :

```swift
enum NutritionJournal {
    @MainActor @discardableResult
    static func addEntry(
        in context: ModelContext, dateKey: DateKey, slot: MealSlot,
        foodName: String, kcal100: Double, protein100: Double,
        carbs100: Double, fat100: Double, grams: Double,
        productCode: String? = nil
    ) throws -> FoodEntry
    @MainActor static func move(
        _ entry: FoodEntry, direction: Int, in context: ModelContext
    ) throws
    @MainActor static func update(
        _ entry: FoodEntry, foodName: String, grams: Double,
        in context: ModelContext
    ) throws
    @MainActor static func delete(
        _ entry: FoodEntry, in context: ModelContext
    ) throws
    @MainActor static func setDayType(
        _ dayType: DayType?, for dateKey: DateKey, in context: ModelContext
    ) throws
}
```

Sémantique (portée de `db/journal.py`) : `addEntry` ajoute **en fin de repas** (`sortOrder` = max du (date, repas) + 1) ; `move` échange les `sortOrder` avec le voisin immédiat du même (date, repas), no-op au bord ; `update` ne touche que libellé et grammes ; `setDayType` upsert le `NutritionDay` de la date (nil = jour sans type, la ligne reste).

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/NutritionJournalTests.swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("NutritionJournal")
@MainActor
struct NutritionJournalTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func addFood(
        _ name: String, to slot: MealSlot, context: ModelContext,
        dateKey: DateKey = DateKey(raw: "2026-08-08")!
    ) throws -> FoodEntry {
        try NutritionJournal.addEntry(
            in: context, dateKey: dateKey, slot: slot, foodName: name,
            kcal100: 100, protein100: 10, carbs100: 20, fat100: 5, grams: 100
        )
    }

    @Test("une nouvelle entrée s'ajoute en fin de son repas")
    func appendsAtEndOfMeal() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)

        let first = try addFood("A", to: breakfast, context: context)
        let second = try addFood("B", to: breakfast, context: context)
        let other = try addFood("C", to: dinner, context: context)

        #expect(first.sortOrder < second.sortOrder)
        // Le compteur est par (date, repas) : le dîner repart de son propre max.
        #expect(other.sortOrder <= second.sortOrder)
        let saved = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(saved.count == 3)
    }

    @Test("monter échange avec le voisin du dessus, no-op en tête")
    func moveUpSwapsWithNeighbour() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let a = try addFood("A", to: slot, context: context)
        let b = try addFood("B", to: slot, context: context)

        try NutritionJournal.move(b, direction: -1, in: context)
        #expect(b.sortOrder < a.sortOrder)

        // B est en tête : remonter encore ne change rien.
        let before = (b.sortOrder, a.sortOrder)
        try NutritionJournal.move(b, direction: -1, in: context)
        #expect((b.sortOrder, a.sortOrder) == before)
    }

    @Test("descendre ne franchit jamais la frontière du repas")
    func moveDownStaysInMeal() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 1, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)
        let a = try addFood("A", to: breakfast, context: context)
        _ = try addFood("B", to: dinner, context: context)

        // A est seul dans son repas : descendre est un no-op même si le
        // dîner contient une entrée au sortOrder supérieur.
        let before = a.sortOrder
        try NutritionJournal.move(a, direction: 1, in: context)
        #expect(a.sortOrder == before)
    }

    @Test("le déplacement ignore les entrées d'une autre date")
    func moveIgnoresOtherDates() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let today = try addFood("A", to: slot, context: context)
        _ = try addFood(
            "Hier", to: slot, context: context,
            dateKey: DateKey(raw: "2026-08-07")!
        )

        let before = today.sortOrder
        try NutritionJournal.move(today, direction: -1, in: context)
        #expect(today.sortOrder == before)
    }

    @Test("l'édition ne touche que le libellé et les grammes")
    func updateKeepsMacros() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let entry = try addFood("A", to: slot, context: context)

        try NutritionJournal.update(
            entry, foodName: "Avoine bio", grams: 55, in: context
        )
        #expect(entry.foodName == "Avoine bio")
        #expect(entry.grams == 55)
        #expect(entry.kcal100 == 100)
        #expect(entry.protein100 == 10)
    }

    @Test("la suppression retire l'entrée du store")
    func deleteRemoves() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let entry = try addFood("A", to: slot, context: context)

        try NutritionJournal.delete(entry, in: context)
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).isEmpty)
    }

    @Test("le jour-type s'upsert sur la date")
    func dayTypeUpserts() throws {
        let context = try makeContext()
        let rest = DayType(name: "repos", kcalTarget: 1800)
        let long = DayType(name: "sortie longue", kcalTarget: 2500)
        context.insert(rest)
        context.insert(long)
        let key = DateKey(raw: "2026-08-08")!

        try NutritionJournal.setDayType(rest, for: key, in: context)
        var days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType?.name == "repos")

        try NutritionJournal.setDayType(long, for: key, in: context)
        days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType?.name == "sortie longue")

        try NutritionJournal.setDayType(nil, for: key, in: context)
        days = try context.fetch(FetchDescriptor<NutritionDay>())
        #expect(days.count == 1)
        #expect(days[0].dayType == nil)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionJournalTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/NutritionJournal.swift
import Foundation
import SwiftData

/// Every write the day screen performs, in one place — the SwiftData
/// counterpart of suivinut's `db/journal.py` mutation functions. Views call
/// these instead of touching the context, so the ordering rules stay
/// testable without UI.
enum NutritionJournal {
    /// Appends at the end of the (day, meal): suivinut used the row id as
    /// sort order for the same effect; here the per-meal max + 1 gives the
    /// identical ordering without depending on an autoincrement.
    @MainActor @discardableResult
    static func addEntry(
        in context: ModelContext, dateKey: DateKey, slot: MealSlot,
        foodName: String, kcal100: Double, protein100: Double,
        carbs100: Double, fat100: Double, grams: Double,
        productCode: String? = nil
    ) throws -> FoodEntry {
        let last = try siblings(of: dateKey.raw, slot: slot, in: context)
            .map(\.sortOrder).max() ?? 0
        let entry = FoodEntry(
            dateKey: dateKey, mealSlot: slot, foodName: foodName,
            kcal100: kcal100, protein100: protein100, carbs100: carbs100,
            fat100: fat100, grams: grams, sortOrder: last + 1,
            productCode: productCode
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    /// Swaps sort orders with the immediate neighbour in the same
    /// (day, meal); nothing happens at the edges — a list that wraps
    /// silently loses your place.
    @MainActor
    static func move(
        _ entry: FoodEntry, direction: Int, in context: ModelContext
    ) throws {
        guard let slot = entry.mealSlot else { return }
        let ordered = try siblings(of: entry.dateKeyRaw, slot: slot, in: context)
            .sorted { $0.sortOrder < $1.sortOrder }
        guard let index = ordered.firstIndex(where: {
            $0.persistentModelID == entry.persistentModelID
        }) else { return }
        let target = index + (direction < 0 ? -1 : 1)
        guard ordered.indices.contains(target) else { return }
        let neighbour = ordered[target]
        swap(&entry.sortOrder, &neighbour.sortOrder)
        try context.save()
    }

    /// Label and quantity only — the per-100 g values were captured at entry
    /// time and stay what was actually eaten.
    @MainActor
    static func update(
        _ entry: FoodEntry, foodName: String, grams: Double,
        in context: ModelContext
    ) throws {
        entry.foodName = foodName
        entry.grams = grams
        try context.save()
    }

    @MainActor
    static func delete(_ entry: FoodEntry, in context: ModelContext) throws {
        context.delete(entry)
        try context.save()
    }

    /// Upsert on the date, like suivinut's `set_day_type`. Clearing keeps
    /// the row with a nil type: a day the user touched is still a day.
    @MainActor
    static func setDayType(
        _ dayType: DayType?, for dateKey: DateKey, in context: ModelContext
    ) throws {
        let raw = dateKey.raw
        let existing = try context.fetch(
            FetchDescriptor<NutritionDay>(
                predicate: #Predicate { $0.dateKeyRaw == raw }
            )
        ).first
        if let existing {
            existing.dayType = dayType
        } else {
            context.insert(NutritionDay(dateKey: dateKey, dayType: dayType))
        }
        try context.save()
    }

    /// Entries of one (day, meal). The date filters in the predicate; the
    /// slot compares in memory — SwiftData predicates on relationships are
    /// not worth the fragility for a handful of rows.
    @MainActor
    private static func siblings(
        of dateKeyRaw: String, slot: MealSlot, in context: ModelContext
    ) throws -> [FoodEntry] {
        let raw = dateKeyRaw
        return try context.fetch(
            FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.dateKeyRaw == raw }
            )
        ).filter { $0.mealSlot?.persistentModelID == slot.persistentModelID }
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionJournal.swift Tests/NutritionJournalTests.swift
git commit -m "feat(alimentation): mutations du journal (ajout, édition, ordre, jour-type)"
```

---

### Task 4: Identité des lignes dans NutritionDayModel

**Files:**
- Modify: `Cairn/Features/Nutrition/NutritionDayModel.swift`
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift` (les deux `ForEach`)
- Test: `Tests/NutritionDayModelTests.swift` (ajouts)

**Interfaces:**
- Consumes: `NutritionDayModel` phase 1.
- Produces: `Row` gagne `entryID: PersistentIdentifier`, `Meal` gagne `slotID: PersistentIdentifier`. Les `ForEach` de la vue passent de `id: \.offset` à `ForEach(model.meals, id: \.slotID)` et `ForEach(meal.rows, id: \.entryID)`. Tasks 5-6 s'appuient sur ces identités pour retrouver le `FoodEntry`/`MealSlot` à modifier.

- [ ] **Step 1: Écrire le test qui échoue** (à ajouter dans `NutritionDayModelTests`)

```swift
    @Test("chaque ligne et chaque repas portent l'identité de leur modèle")
    func rowsCarryModelIdentity() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        context.insert(slot)
        let key = DateKey(raw: "2026-08-08")!
        let entry = FoodEntry(
            dateKey: key, mealSlot: slot, foodName: "Skyr",
            kcal100: 57, protein100: 10, carbs100: 4, fat100: 0,
            grams: 150, sortOrder: 0
        )
        context.insert(entry)

        let model = NutritionDayModel.compute(
            entries: [entry], slots: [slot], notes: [],
            dayType: nil, proteinTargetG: 130, fatTargetG: 66
        )
        #expect(model.meals[0].slotID == slot.persistentModelID)
        #expect(model.meals[0].rows[0].entryID == entry.persistentModelID)
    }
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/NutritionDayModelTests 2>&1 | tail -5`
Expected: échec de compilation (`slotID`/`entryID` inconnus).

- [ ] **Step 3: Implémenter**

Dans `NutritionDayModel.swift` :

```swift
    struct Row: Equatable {
        var entryID: PersistentIdentifier
        var name: String
        var grams: Double
        var macros: Macros
    }

    struct Meal: Equatable {
        var slotID: PersistentIdentifier
        var slotName: String
        var rows: [Row]
        var consumed: Macros
        var target: Macros?
        var note: String?
    }
```

et dans `compute`, compléter les constructions :

```swift
        let meals = orderedSlots.enumerated().map { index, slot in
            Meal(
                slotID: slot.persistentModelID,
                slotName: slot.name,
                rows: mealEntries[index].map {
                    Row(
                        entryID: $0.persistentModelID, name: $0.foodName,
                        grams: $0.grams, macros: Macros(of: $0)
                    )
                },
                consumed: mealConsumed[index],
                target: targets[index],
                note: notes.first {
                    $0.mealSlot?.persistentModelID == slot.persistentModelID
                }?.note
            )
        }
```

Dans `NutritionDayView.swift`, remplacer les deux `ForEach` :

```swift
                ForEach(model.meals, id: \.slotID) { meal in
                    mealSection(meal)
                }
```

```swift
                    ForEach(meal.rows, id: \.entryID) { row in
```

(supprimer les `Array(...enumerated())` correspondants et les paramètres `_,` devenus inutiles).

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2, puis la suite complète `-only-testing:CairnTests`.
Expected: PASS partout (le build de la vue confirme que les `ForEach` compilent).

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionDayModel.swift Cairn/Features/Nutrition/NutritionDayView.swift Tests/NutritionDayModelTests.swift
git commit -m "feat(alimentation): les lignes du jour portent l'identité de leurs modèles"
```

---

### Task 5: Sheet d'ajout d'aliment

**Files:**
- Create: `Cairn/Features/Nutrition/AddFoodSheet.swift`
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift` (bouton « Ajouter… » + présentation)

**Interfaces:**
- Consumes: `FoodCatalog` (Task 2), `NutritionJournal.addEntry` (Task 3), `Meal.slotID` (Task 4), `@Query slots` existant de la vue.
- Produces: `struct AddFoodSheet: View` — `init(slot: MealSlot, dateKey: DateKey)`. La vue du jour la présente via `.sheet(item: $addTargetSlot)` (`MealSlot` est `Identifiable` via `PersistentModel`).

Pas de test unitaire (UI sur logique déjà testée) — le build + la suite complète verte sont la barre, plus la vérification visuelle en fin de phase.

- [ ] **Step 1: Créer la sheet**

```swift
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
```

- [ ] **Step 2: Brancher la présentation dans la vue du jour**

Dans `NutritionDayView.swift` :

1. Ajouter l'état :

```swift
    @State private var addTargetSlot: MealSlot?
```

2. Dans `mealSection`, l'en-tête de repas gagne le bouton (après le `Text(mealFigure(meal))`) :

```swift
                Button {
                    addTargetSlot = slots.first {
                        $0.persistentModelID == meal.slotID
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Ajouter un aliment à \(meal.slotName)")
```

3. Sur le `ScrollView` de `journal`, attacher la sheet :

```swift
        .sheet(item: $addTargetSlot) { slot in
            AddFoodSheet(slot: slot, dateKey: dateKey)
        }
```

- [ ] **Step 3: Builder et lancer la suite complète**

Run:
```bash
xcodegen generate && xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | tail -3
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests 2>&1 | tail -3
```
Expected: build OK, suite complète verte.

- [ ] **Step 4: Commit**

```bash
git add Cairn/Features/Nutrition/AddFoodSheet.swift Cairn/Features/Nutrition/NutritionDayView.swift
git commit -m "feat(alimentation): sheet d'ajout d'aliment (recherche catalogue et saisie manuelle)"
```

---

### Task 6: Actions de ligne, jour-type et finitions

**Files:**
- Create: `Cairn/Features/Nutrition/EditEntrySheet.swift`
- Modify: `Cairn/Features/Nutrition/NutritionDayView.swift`

**Interfaces:**
- Consumes: `NutritionJournal.move/update/delete/setDayType` (Task 3), `Row.entryID` (Task 4), `@Query` existants.
- Produces: l'écran du jour éditable au complet — menu contextuel par ligne (Éditer…, Monter, Descendre, Supprimer), menu jour-type dans le bandeau, alerte de résultat d'import, titre de date à la typographie française.

- [ ] **Step 1: Créer la sheet d'édition**

```swift
// Cairn/Features/Nutrition/EditEntrySheet.swift
import SwiftUI
import SwiftData

/// Label and grams only: the per-100 g values were captured at entry time
/// and editing them would rewrite what was actually eaten.
struct EditEntrySheet: View {
    let entry: FoodEntry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var grams: Double
    @State private var errorMessage: String?

    init(entry: FoodEntry) {
        self.entry = entry
        _name = State(initialValue: entry.foodName)
        _grams = State(initialValue: entry.grams)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modifier l'aliment")
                .font(.headline)
            TextField("Nom", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("Quantité")
                TextField("g", value: $grams, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("g")
                Spacer()
                Text("\(Int((entry.kcal100 * grams / 100).rounded())) kcal")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        grams <= 0
                        || name.trimmingCharacters(in: .whitespaces).isEmpty
                    )
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }

    private func save() {
        do {
            try NutritionJournal.update(
                entry,
                foodName: name.trimmingCharacters(in: .whitespaces),
                grams: grams, in: modelContext
            )
            dismiss()
        } catch {
            errorMessage =
                "Votre modification n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Actions de ligne dans la vue du jour**

Dans `NutritionDayView.swift` :

1. États et requête supplémentaires :

```swift
    @State private var editingEntry: FoodEntry?
    @State private var writeFailureMessage: String?
    // Sorted the way suivinut lists day types: by target then name, so the
    // menu reads from rest day to biggest day.
    @Query(sort: [
        SortDescriptor(\DayType.kcalTarget), SortDescriptor(\DayType.name),
    ]) private var dayTypes: [DayType]
```

2. Dans `mealSection`, sur chaque ligne (le `GridRow` du `ForEach(meal.rows, id: \.entryID)`), attacher le menu contextuel. Un modificateur sur `GridRow` s'applique à chaque cellule — le clic droit fonctionne donc sur toute la ligne :

```swift
                        .contextMenu {
                            Button("Éditer…") {
                                editingEntry = entry(for: row.entryID)
                            }
                            Button("Monter") { move(row.entryID, direction: -1) }
                            Button("Descendre") { move(row.entryID, direction: 1) }
                            Divider()
                            Button("Supprimer", role: .destructive) {
                                deleteEntry(row.entryID)
                            }
                        }
```

3. Les aides correspondantes (dans la vue) :

```swift
    private func entry(for id: PersistentIdentifier) -> FoodEntry? {
        entries.first { $0.persistentModelID == id }
    }

    private func move(_ id: PersistentIdentifier, direction: Int) {
        guard let entry = entry(for: id) else { return }
        do {
            try NutritionJournal.move(entry, direction: direction, in: modelContext)
        } catch {
            writeFailureMessage =
                "Le déplacement n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }

    private func deleteEntry(_ id: PersistentIdentifier) {
        guard let entry = entry(for: id) else { return }
        do {
            try NutritionJournal.delete(entry, in: modelContext)
        } catch {
            writeFailureMessage =
                "Votre suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
```

4. Présentations et alertes, sur le `ScrollView` de `journal` (à côté de la sheet d'ajout de la Task 5) :

```swift
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(entry: entry)
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
```

- [ ] **Step 3: Menu jour-type dans le bandeau**

Dans `header(_:)`, remplacer la puce statique (`Text(dayTypeName)` / `Text("Aucun jour-type")`) par un menu :

```swift
            Menu {
                ForEach(dayTypes) { dayType in
                    Button("\(dayType.name) — \(dayType.kcalTarget) kcal") {
                        setDayType(dayType)
                    }
                }
                Divider()
                Button("Aucun") { setDayType(nil) }
            } label: {
                if let dayTypeName = model.dayTypeName {
                    Text(dayTypeName)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                } else {
                    Text("Choisir un jour-type")
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
```

avec l'aide :

```swift
    private func setDayType(_ dayType: DayType?) {
        do {
            try NutritionJournal.setDayType(dayType, for: dateKey, in: modelContext)
        } catch {
            writeFailureMessage =
                "Le jour-type n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 4: Finitions reportées de la phase 1**

Toujours dans `NutritionDayView.swift` :

1. **Titre de date en typographie française** — remplacer, dans `header`,
   `Text(Format.fullDate(dateKey.date()).capitalized)` par :

```swift
            Text(dayTitle)
```

   avec :

```swift
    /// "Vendredi 8 août 2026" : only the first letter is raised —
    /// `.capitalized` would write every word capital, which French dates
    /// never do.
    private var dayTitle: String {
        let raw = Format.fullDate(dateKey.date())
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
```

2. **Résultat d'import visible** — le message de succès ne s'affichait
   jamais (la vue bascule vers le journal dès que l'import crée les repas).
   Remplacer l'affichage inline `if let importMessage { Text(...) }` de
   `onboarding` par une alerte attachée au `Group`/branche racine de `body`
   (donc visible quel que soit l'écran affiché) :

```swift
        .alert(
            "Import suivinut",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
```

   Note : `body` étant un `if/else`, l'envelopper dans un `Group { ... }`
   pour porter l'alerte (même motif que `RootView`).

- [ ] **Step 5: Builder et lancer la suite complète**

Run:
```bash
xcodegen generate && xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | tail -3
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests 2>&1 | tail -3
```
Expected: build OK, suite complète verte.

- [ ] **Step 6: Vérification visuelle**

Lancer l'app en mode démo (`STRAVALOCAL_DEMO=1`, store séparé) : « Commencer sans importer », puis ajouter un aliment en manuel, vérifier le menu contextuel (éditer, monter/descendre, supprimer), choisir un jour-type, vérifier que les jauges suivent. Si un `off.db` est présent dans Application Support, vérifier la recherche.

- [ ] **Step 7: Commit**

```bash
git add Cairn/Features/Nutrition/EditEntrySheet.swift Cairn/Features/Nutrition/NutritionDayView.swift
git commit -m "feat(alimentation): édition, réordonnancement, suppression et jour-type depuis l'écran"
```

---

## Après cette phase

Phase 3 (plan séparé) : recettes (picker + « enregistrer ce repas comme recette » + éditeur), favoris (étoile + onglet dans la sheet d'ajout), notes de repas éditables, onglet Réglages Nutrition (cibles, jours-types, % repas, réimport avec porte propre et contexte dédié). Les interfaces à respecter : `NutritionJournal`, `FoodCatalog`, `AddFoodSheet` (son segment Favoris s'ajoutera), `NutritionSettings`.

Reste au ledger de la phase 1, à traiter en phase 3+ : porte d'import `slots.isEmpty` vs spec (« aucun FoodEntry ») quand le bouton Réglages arrivera ; contexte SwiftData dédié pour l'import ; volet détail activité résiduel (phase 6).
