import Foundation
import SwiftData

@Model
final class Lap {
    var stravaID: Int64 = 0
    var lapIndex: Int = 0
    var name: String = ""
    var distance: Double = 0
    var movingTime: Int = 0
    var elapsedTime: Int = 0
    var totalElevationGain: Double = 0
    var averageSpeed: Double = 0
    var maxSpeed: Double = 0
    var averageHeartrate: Double?
    var averageCadence: Double?
    /// Index range into the activity's streams, so a lap can be highlighted.
    var startIndex: Int = 0
    var endIndex: Int = 0

    var activity: Activity?

    init(stravaID: Int64, lapIndex: Int) {
        self.stravaID = stravaID
        self.lapIndex = lapIndex
    }
}
