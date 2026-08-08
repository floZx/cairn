import Foundation
import SwiftData

/// A meal of the day — "Petit-déj", "Dîner" — with its share of the daily
/// calorie plan in percent. 0 % is a valid slot (a snack that borrows from
/// the day rather than owning a share).
@Model
final class MealSlot {
    var name: String = ""
    var sortOrder: Int = 0
    var targetPct: Int = 0

    init(name: String, sortOrder: Int = 0, targetPct: Int = 0) {
        self.name = name
        self.sortOrder = sortOrder
        self.targetPct = targetPct
    }
}
