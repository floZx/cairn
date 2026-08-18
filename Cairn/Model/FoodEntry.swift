import Foundation
import SwiftData

/// One food eaten at one meal. The per-100 g values are copied here at entry
/// time — denormalised on purpose, so history stays true even if the OFF
/// catalog is rebuilt or deleted. `productCode` is only a reference back.
@Model
final class FoodEntry {
    #Index<FoodEntry>([\.dateKeyRaw])

    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

    var dateKeyRaw: String = ""
    var mealSlot: MealSlot?
    var productCode: String?
    var foodName: String = ""
    var kcal100: Double = 0
    var protein100: Double = 0
    var carbs100: Double = 0
    var fat100: Double = 0
    /// Les fibres pour cent grammes, **facultatives**.
    ///
    /// Nulles et non zéro : Open Food Facts ne les connaît que pour cinq
    /// produits sur six, et un aliment qui n'a rien annoncé n'en contient pas
    /// zéro — il n'a rien dit. Confondre les deux ferait d'un total partiel un
    /// total faux, et c'est précisément ce que la jauge doit avouer.
    var fiber100: Double?
    var grams: Double = 0
    var sortOrder: Int = 0

    init(
        dateKey: DateKey, mealSlot: MealSlot?, foodName: String,
        kcal100: Double, protein100: Double, carbs100: Double,
        fat100: Double, grams: Double, sortOrder: Int = 0,
        productCode: String? = nil, fiber100: Double? = nil
    ) {
        self.dateKeyRaw = dateKey.raw
        self.mealSlot = mealSlot
        self.foodName = foodName
        self.kcal100 = kcal100
        self.protein100 = protein100
        self.carbs100 = carbs100
        self.fat100 = fat100
        self.fiber100 = fiber100
        self.grams = grams
        self.sortOrder = sortOrder
        self.productCode = productCode
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
