import Foundation
import SwiftData
import Observation

/// Wires the app together in one place. Views receive it through the
/// environment and never build a client, engine or store themselves.
@MainActor
@Observable
final class AppEnvironment {
    let store: SecretStore
    let client: StravaClient
    let oauth: OAuthFlow
    let engine: SyncEngine
    let progress: SyncProgress

    var isAuthenticated: Bool
    var hasCredentials: Bool
    var athleteName: String?
    var errorMessage: String?

    private var runningTask: Task<Void, Never>?

    init(container: ModelContainer) {
        let store = KeychainStore()
        let progress = SyncProgress()
        let client = StravaClient(store: store)

        self.store = store
        self.client = client
        self.progress = progress
        self.oauth = OAuthFlow(store: store)
        self.engine = SyncEngine(
            source: client, container: container, progress: progress
        )
        self.isAuthenticated = store.tokens() != nil
        self.hasCredentials = store.credentials() != nil
    }

    func refreshAuthenticationState() {
        isAuthenticated = store.tokens() != nil
        hasCredentials = store.credentials() != nil
    }

    func saveCredentials(clientID: String, clientSecret: String) {
        do {
            try store.save(
                StravaCredentials(
                    clientID: clientID.trimmingCharacters(in: .whitespaces),
                    clientSecret: clientSecret.trimmingCharacters(in: .whitespaces)
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = "Impossible d'enregistrer les identifiants : \(error.localizedDescription)"
        }
        refreshAuthenticationState()
    }

    func connect() async {
        do {
            let athlete = try await oauth.authorize()
            athleteName = [athlete?.firstname, athlete?.lastname]
                .compactMap { $0 }.joined(separator: " ")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshAuthenticationState()
    }

    func disconnect() {
        try? store.clearTokens()
        athleteName = nil
        refreshAuthenticationState()
    }

    /// Full sync. Guarded against overlapping runs — two concurrent syncs would
    /// double-spend the API quota for nothing.
    func syncNow() {
        guard runningTask == nil, isAuthenticated else { return }
        runningTask = Task { [engine] in
            do {
                try await engine.syncAll()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            runningTask = nil
        }
    }

    func syncSummariesOnly() {
        guard runningTask == nil, isAuthenticated else { return }
        runningTask = Task { [engine] in
            do {
                try await engine.syncAthlete()
                try await engine.syncSummaries()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            runningTask = nil
        }
    }

    func cancelSync() {
        runningTask?.cancel()
        runningTask = nil
    }

    func loadDetail(stravaID: Int64) {
        Task { [engine] in
            try? await engine.fetchDetailIfNeeded(stravaID: stravaID)
        }
    }
}
