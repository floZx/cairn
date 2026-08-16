import Foundation
import SwiftData

/// A free-form note on one (day, meal) pair. Uniqueness is enforced by the
/// fetch-or-create call sites rather than a compound constraint — SwiftData
/// unique constraints on relationships are not worth the migration risk.
@Model
final class MealNote {
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

    var dateKeyRaw: String = ""
    var mealSlot: MealSlot?
    var note: String = ""

    init(dateKey: DateKey, mealSlot: MealSlot?, note: String) {
        self.dateKeyRaw = dateKey.raw
        self.mealSlot = mealSlot
        self.note = note
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
