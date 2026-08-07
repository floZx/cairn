import Foundation
import SwiftData

@Model
final class Athlete {
    var stravaID: Int64 = 0
    var firstName: String = ""
    var lastName: String = ""
    var city: String?
    var country: String?
    var profileImageURL: String?
    var weight: Double?
    var updatedAt: Date = Date.distantPast

    init(stravaID: Int64) { self.stravaID = stravaID }

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
}
