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
        do {
            return try importAll(journalPath: journalPath)
        } catch {
            // `rollback()` discards ALL pending changes in `context`, not just
            // this import's. That is safe here because the import only runs
            // while the nutrition store is empty, and every call site passes
            // the main context with no other pending edits at that point.
            context.rollback()
            throw error
        }
    }

    private func importAll(journalPath: String) throws -> Summary {
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

        var recipeItemCounts: [Int64: Int] = [:]
        for row in try db.rows("""
            SELECT recipe_id, food_name, product_code, kcal_100g,
                   protein_100g, carbs_100g, fat_100g, grams
            FROM recipe_items ORDER BY id
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
            let order = recipeItemCounts[recipeID, default: 0]
            recipeItemCounts[recipeID] = order + 1
            item.sortOrder = order
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
