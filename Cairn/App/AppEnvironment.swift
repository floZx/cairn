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
    private let defaults = UserDefaults.standard

    /// Installed by `RootView` so the menu bar can reach the window's own state.
    ///
    /// Nil until a window exists, which is exactly what disables the menu items:
    /// there is nothing to add an activity to before then.
    var requestNewActivity: (() -> Void)?
    var requestEditSelection: (() -> Void)?
    var requestDeleteSelection: (() -> Void)?
    var requestToggleFavorite: (() -> Void)?
    var requestImportGPX: (() -> Void)?
    var requestExportGPX: (() -> Void)?

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
            let name = [athlete?.firstname, athlete?.lastname]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            athleteName = name.isEmpty ? nil : name
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

    /// Full sync: summaries, gear, then every pending stream.
    func syncNow() {
        runSync { [engine] in try await engine.syncAll() }
    }

    /// The cheap pass only — a couple of requests whatever the history size.
    func syncSummariesOnly() {
        runSync { [engine] in
            try await engine.syncAthlete()
            try await engine.syncSummaries()
        }
    }

    /// Re-reads every summary from Strava, picking up anything edited there
    /// after the fact. Streams are left as they are.
    func resyncEverything() {
        runSync { [engine] in try await engine.resyncEverything() }
    }

    /// Whether launching the app looks for new activities.
    ///
    /// Only the summary pass runs: a couple of requests whatever the size of the
    /// history, so opening the app is never a surprise dent in the API quota.
    /// Detailed tracks stay on demand, via ⌘R.
    var syncsOnLaunch: Bool {
        get { defaults.object(forKey: Self.syncOnLaunchKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.syncOnLaunchKey) }
    }

    private static let syncOnLaunchKey = "syncsOnLaunch"

    func syncOnLaunch() {
        restoreLastSyncDate()
        guard syncsOnLaunch, isAuthenticated else { return }
        syncSummariesOnly()
    }

    /// Reads the last successful run back out of the store.
    ///
    /// `SyncProgress` is session state: the engine only sets `lastRunAt` when a
    /// run finishes, so without this the app claimed it had never synced after
    /// every launch. Unconditional — the date is worth showing whether or not
    /// this launch goes on to sync, and whether or not anyone is signed in.
    func restoreLastSyncDate() {
        Task {
            guard let date = try? await engine.stateSnapshot().lastRunAt else { return }
            // Only while still empty: the launch sync starts immediately after
            // this and may well finish first, and an awaited read must not put
            // the older date back over it.
            guard progress.lastRunAt == nil else { return }
            progress.lastRunAt = date
        }
    }

    /// Runs one sync operation with the guarantees every entry point needs:
    /// no overlapping runs (two concurrent syncs would double-spend the API
    /// quota), the error surfaced to the UI, and the slot released only by the
    /// task that owns it — see `cancelSync` for why.
    private func runSync(_ operation: @escaping @Sendable () async throws -> Void) {
        guard runningTask == nil, isAuthenticated else { return }
        let task = Task {
            do {
                try await operation()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        runningTask = task
        Task {
            _ = await task.value
            if runningTask == task { runningTask = nil }
        }
    }

    /// Cancellation is cooperative, so the slot can only be released by the
    /// task itself once it has actually unwound — clearing it here would let
    /// a second sync start alongside the dying one.
    func cancelSync() {
        guard let task = runningTask else { return }
        task.cancel()
        Task { _ = await task.value }
    }

    func loadDetail(stravaID: Int64) {
        Task { [engine] in
            try? await engine.fetchDetailIfNeeded(stravaID: stravaID)
        }
    }
}
