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
        }
    }
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
