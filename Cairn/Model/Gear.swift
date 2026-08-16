import Foundation
import SwiftData

@Model
final class Gear {
    #Unique<Gear>([\.stravaID])

    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString

    var stravaID: String = ""
    var name: String = ""
    var brandName: String?
    var modelName: String?
    var isBike: Bool = true
    var totalDistance: Double = 0

    init(stravaID: String, name: String) {
        self.stravaID = stravaID
        self.name = name
    }
}
