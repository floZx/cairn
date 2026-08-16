import Foundation
import SwiftData

/// One weigh-in per day at most — entering a day twice replaces it, which
/// the unique key enforces at the store level.
@Model
final class WeightEntry {
    #Unique<WeightEntry>([\.dateKeyRaw])

    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

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
