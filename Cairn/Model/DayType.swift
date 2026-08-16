import Foundation
import SwiftData

/// A named calorie target — "repos", "sortie longue" — assigned to a day.
/// The athlete's need varies with training, so the target belongs to a
/// reusable day *type* rather than to each date.
@Model
final class DayType {
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

    var name: String = ""
    var kcalTarget: Int = 0
    var sortOrder: Int = 0

    init(name: String, kcalTarget: Int, sortOrder: Int = 0) {
        self.name = name
        self.kcalTarget = kcalTarget
        self.sortOrder = sortOrder
    }
}
