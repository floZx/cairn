import Foundation
import SwiftData

@Model
final class Gear {
    #Unique<Gear>([\.stravaID])

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
