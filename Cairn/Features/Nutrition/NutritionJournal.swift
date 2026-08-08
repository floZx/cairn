import Foundation
import SwiftData

/// Identity of a favorite: name + optional catalog code, exactly suivinut's
/// `(food_name, product_code)` pair — a branded product and a homonymous
/// manual food are two different favorites.
struct FavoriteKey: Hashable {
    var foodName: String
    var productCode: String?
}

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
