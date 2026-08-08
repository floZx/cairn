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
