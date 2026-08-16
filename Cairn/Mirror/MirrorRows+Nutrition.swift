import Foundation

// MARK: - DayType

extension DayType: MirrorRow {
    static var mirrorTable: String { "day_type" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "name": .string(name),
            "kcal_target": .from(kcalTarget),
            "sort_order": .from(sortOrder),
        ]
    }
}

// MARK: - MealSlot

extension MealSlot: MirrorRow {
    static var mirrorTable: String { "meal_slot" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "name": .string(name),
            "sort_order": .from(sortOrder),
            "target_pct": .from(targetPct),
        ]
    }
}

// MARK: - NutritionDay

extension NutritionDay: MirrorRow {
    static var mirrorTable: String { "nutrition_day" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "date_key_raw": .string(dateKeyRaw),
            "day_type_uuid": .from(dayType?.uuid),
        ]
    }
}

// MARK: - FoodEntry

extension FoodEntry: MirrorRow {
    static var mirrorTable: String { "food_entry" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "date_key_raw": .string(dateKeyRaw),
            "meal_slot_uuid": .from(mealSlot?.uuid),
            "product_code": .from(productCode),
            "food_name": .string(foodName),
            "kcal100": .double(kcal100),
            "protein100": .double(protein100),
            "carbs100": .double(carbs100),
            "fat100": .double(fat100),
            "grams": .double(grams),
            "sort_order": .from(sortOrder),
        ]
    }
}

// MARK: - MealNote

extension MealNote: MirrorRow {
    static var mirrorTable: String { "meal_note" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "date_key_raw": .string(dateKeyRaw),
            "meal_slot_uuid": .from(mealSlot?.uuid),
            "note": .string(note),
        ]
    }
}

// MARK: - Recipe

extension Recipe: MirrorRow {
    static var mirrorTable: String { "recipe" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "name": .string(name),
            "meal_slot_uuid": .from(mealSlot?.uuid),
        ]
    }
}

// MARK: - RecipeItem

extension RecipeItem: MirrorRow {
    static var mirrorTable: String { "recipe_item" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "recipe_uuid": .from(recipe?.uuid),
            "food_name": .string(foodName),
            "product_code": .from(productCode),
            "kcal100": .double(kcal100),
            "protein100": .double(protein100),
            "carbs100": .double(carbs100),
            "fat100": .double(fat100),
            "grams": .double(grams),
            "sort_order": .from(sortOrder),
        ]
    }
}

// MARK: - FavoriteFood

extension FavoriteFood: MirrorRow {
    static var mirrorTable: String { "favorite_food" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "food_name": .string(foodName),
            "product_code": .from(productCode),
            "kcal100": .double(kcal100),
            "protein100": .double(protein100),
            "carbs100": .double(carbs100),
            "fat100": .double(fat100),
            "grams": .double(grams),
        ]
    }
}

// MARK: - WeightEntry
//
// Weighing in has no home of its own among the eleven files the brief names,
// so it lands here rather than beside the activity models: a scale reading is
// closer kin to a food entry than to a Strava outing. The schema's own
// comment on `weight_entry` is the one that matters, though: `date_key_raw`
// and `weight_kg` are the only names that ever existed on this model — the
// plan's original `day` / `kilograms` template never did.

extension WeightEntry: MirrorRow {
    static var mirrorTable: String { "weight_entry" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "date_key_raw": .string(dateKeyRaw),
            "weight_kg": .double(weightKg),
            "note": .from(note),
        ]
    }
}
