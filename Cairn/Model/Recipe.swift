import Foundation
import SwiftData

/// A reusable set of foods applied to a meal in one gesture.
@Model
final class Recipe {
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

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
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

    var recipe: Recipe?
    var foodName: String = ""
    var productCode: String?
    var kcal100: Double = 0
    var protein100: Double = 0
    var carbs100: Double = 0
    var fat100: Double = 0
    /// Facultatives, comme sur `FoodEntry` et pour la même raison.
    var fiber100: Double?
    var grams: Double = 0
    /// Display and apply order inside the recipe. suivinut ordered by row id;
    /// items imported before this field exists stay at 0 and fall back to
    /// name order — the best that can be recovered.
    var sortOrder: Int = 0

    init(
        foodName: String, kcal100: Double, protein100: Double,
        carbs100: Double, fat100: Double, grams: Double,
        productCode: String? = nil, fiber100: Double? = nil
    ) {
        self.foodName = foodName
        self.kcal100 = kcal100
        self.protein100 = protein100
        self.carbs100 = carbs100
        self.fat100 = fat100
        self.fiber100 = fiber100
        self.grams = grams
        self.productCode = productCode
    }
}

extension Recipe {
    /// Items in stable display order.
    var orderedItems: [RecipeItem] {
        (items ?? []).sorted {
            ($0.sortOrder, $0.foodName) < ($1.sortOrder, $1.foodName)
        }
    }
}
