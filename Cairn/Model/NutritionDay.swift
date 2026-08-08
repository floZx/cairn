import Foundation
import SwiftData

/// One journal day's metadata — today just which day type applies. Entries
/// are keyed by date string, not by this object: a day with meals but no
/// chosen type simply has no `NutritionDay` row, exactly like suivinut.
@Model
final class NutritionDay {
    #Unique<NutritionDay>([\.dateKeyRaw])

    var dateKeyRaw: String = ""
    @Relationship(deleteRule: .nullify)
    var dayType: DayType?

    init(dateKey: DateKey, dayType: DayType? = nil) {
        self.dateKeyRaw = dateKey.raw
        self.dayType = dayType
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }
}
