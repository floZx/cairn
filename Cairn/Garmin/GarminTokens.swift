import Foundation

// Apart from `GarminClient` so that `TokenStore` can be compiled without it:
// `cairn-note` reads the mirror session from the same Keychain store, and
// the client would bring the whole Garmin import along.

/// What Garmin Connect hands back once signed in, kept in the Keychain.
///
/// No password in here: it is typed once in the settings, sent to Garmin, and
/// forgotten. The refresh token is what keeps the connection alive afterwards.
struct GarminTokens: Sendable, Equatable, Codable {
    var accessToken: String
    var refreshToken: String
    /// The DI client the token was issued to. A refresh has to present the
    /// same one, and it is read back from the token itself when it says so.
    var clientID: String
    var displayName: String?

    /// Read from the token's own `exp`, fifteen minutes early — the margin
    /// `garminconnect` uses. Nil when the token doesn't say, in which case it
    /// is used until Garmin answers 401.
    var expiresSoon: Bool {
        guard let exp = GarminJWT.claims(accessToken)?["exp"] as? Double else { return false }
        return Date().timeIntervalSince1970 > exp - 900
    }
}

/// Reads a JWT's claims without checking its signature — Garmin holds the
/// key. Only ever used to learn what the token says about itself.
enum GarminJWT {
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
