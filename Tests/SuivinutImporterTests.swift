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

        // The real home directory may itself hold a suivinut install (as it
        // does on the machine this was developed on) — a fake home keeps
        // this test about "no catalog found" rather than "no catalog on
        // this particular machine".
        let copied = try SuivinutImporter.copyCatalog(
            nextTo: journal, to: destination, fileManager: HomelessFileManager()
        )
        #expect(copied == nil)
    }
}

/// A `FileManager` whose home directory never exists, so the fallback
/// candidate in `copyCatalog` reliably misses regardless of what is
/// actually installed on the machine running the tests.
private final class HomelessFileManager: FileManager {
    override var homeDirectoryForCurrentUser: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "no-home-\(UUID().uuidString)")
    }
}
