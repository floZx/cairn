import Foundation
import SwiftData

/// One weigh-in per day at most — entering a day twice replaces it, which
/// the unique key enforces at the store level.
@Model
final class WeightEntry {
    #Unique<WeightEntry>([\.dateKeyRaw])

    var dateKeyRaw: String = ""
    var weightKg: Double = 0
    var note: String?

    init(dateKey: DateKey, weightKg: Double, note: String? = nil) {
        self.dateKeyRaw = dateKey.raw
        self.weightKg = weightKg
        self.note = note
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
