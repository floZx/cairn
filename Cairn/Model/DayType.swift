import Foundation
import SwiftData

/// A named calorie target — "repos", "sortie longue" — assigned to a day.
/// The athlete's need varies with training, so the target belongs to a
/// reusable day *type* rather than to each date.
@Model
final class DayType {
    var name: String = ""
    var kcalTarget: Int = 0
    var sortOrder: Int = 0

    init(name: String, kcalTarget: Int, sortOrder: Int = 0) {
        self.name = name
        self.kcalTarget = kcalTarget
        self.sortOrder = sortOrder
    }
}
