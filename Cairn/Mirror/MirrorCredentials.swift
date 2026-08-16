import Foundation

struct MirrorCredentials: Sendable, Equatable, Codable {
    let projectURL: URL
    let anonKey: String
}

struct MirrorSession: Sendable, Equatable, Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String

    /// Treated as expired five minutes early, same margin as `StravaTokens`:
    /// a long push shouldn't start on a token that dies mid-flight.
    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 300
    }
}
