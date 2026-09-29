import Foundation

enum StravaError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case notAuthenticated
    case invalidResponse
    case http(Int, String)
    case tokenRefreshRejected
    case oauthCancelled
    case oauthStateMismatch
    case oauthDenied(String)
    case oauthTimedOut
    case browserLaunchFailed
    case loopbackUnavailable(String)
    case writeNotAuthorized

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Renseignez le Client ID et le Client Secret de votre application Strava dans les réglages."
        case .notAuthenticated:
            "Vous n'êtes pas connecté à Strava."
        case .invalidResponse:
            "Réponse inattendue de Strava."
        case let .http(status, message):
            "Strava a répondu \(status) : \(message)"
        case .tokenRefreshRejected:
            "L'autorisation Strava a expiré ou été révoquée. Reconnectez-vous."
        case .oauthCancelled:
            "Connexion annulée."
        case .oauthStateMismatch:
            "La réponse d'autorisation ne correspond pas à la demande. Réessayez."
        case let .oauthDenied(reason):
            "Strava a refusé l'autorisation : \(reason)"
        case .oauthTimedOut:
            "L'autorisation Strava n'a pas abouti à temps. Réessayez."
        case .browserLaunchFailed:
            "Impossible d'ouvrir le navigateur pour autoriser l'accès à Strava."
        case let .loopbackUnavailable(reason):
            "Impossible d'ouvrir le port local d'autorisation : \(reason)"
        case .writeNotAuthorized:
            "Strava n'autorise pas encore Cairn à modifier vos activités : déconnectez puis reconnectez Strava dans les réglages."
        }
    }
}

/// What a token endpoint's refusal means.
enum TokenRefresh {
    /// Whether the grant itself is gone: 400 (`invalid_grant`) or 401, the
    /// two answers OAuth servers give a refresh token they no longer honour.
    ///
    /// Anything else — a 5xx, a 429, a maintenance page, a body that does not
    /// decode — says the server is unwell, not that the grant was withdrawn.
    /// Dropping the tokens then signed the user out of Strava or Supabase for
    /// an outage of a few minutes, with a fresh authorisation to go through.
    static func isRevoked(status: Int) -> Bool { status == 400 || status == 401 }
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        return (data, http)
    }
}
