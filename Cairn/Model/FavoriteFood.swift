import Foundation
import SwiftData

/// A recurring food kept one click away, with its usual serving in grams.
@Model
final class FavoriteFood {
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

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
