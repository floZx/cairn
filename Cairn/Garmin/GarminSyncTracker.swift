import Foundation
import Observation

/// Where each activity stands with Garmin Connect, as the detail pane shows it.
enum GarminSyncState: Equatable, Sendable {
    /// Never looked at, or changed in Cairn since it was sent.
    case unknown
    case checking
    /// What Cairn says is what Garmin says — sent from here, or found so.
    case synced
    /// Garmin differs on at least one field.
    case needsSync
    /// No Garmin activity to compare with, or Garmin couldn't be asked.
    /// Said by saying nothing: an activity typed in by hand has no Garmin
    /// twin, and a line announcing it on every such activity would be noise.
    case unavailable
}

/// Remembers which activities are in step with Garmin, and checks the others
/// in the background when they are opened.
///
/// Once synced, an activity isn't checked again on its own: opening it costs
/// no request. What is remembered is the signature of what was sent
/// (`GarminSource.signature`), so editing the title in Cairn makes it
/// « unknown » again and the next opening looks.
///
/// Kept in the preferences rather than on `Activity`: a field there is a
/// write the mirror would push to Supabase, for a fact that only means
/// something on this Mac, signed in to this Garmin account. Losing it costs
/// one background check per activity, nothing more.
@MainActor
@Observable
final class GarminSyncTracker {
    static let storageKey = "garminSyncedSignatures"

    private let client: GarminClient
    private let defaults: UserDefaults
    /// Activity uuid → signature of what Garmin was last found to say.
    private var synced: [String: String]
    /// What this session's checks found, for activities not in step. Kept
    /// with the signature it was found for, so it lapses on an edit.
    private var checked: [String: (signature: String, state: GarminSyncState)] = [:]

    init(client: GarminClient, defaults: UserDefaults) {
        self.client = client
        self.defaults = defaults
        synced = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    func state(uuid: String, source: GarminSource) -> GarminSyncState {
        let signature = source.signature
        if synced[uuid] == signature { return .synced }
        if let found = checked[uuid], found.signature == signature { return found.state }
        return .unknown
    }

    /// Looks at Garmin only for an activity in the « unknown » state; any
    /// other has already been answered, this session or before.
    func checkIfNeeded(uuid: String, source: GarminSource) async {
        guard state(uuid: uuid, source: source) == .unknown else { return }
        let signature = source.signature
        checked[uuid] = (signature, .checking)
        do {
            if let comparison = try await client.compare(source) {
                record(comparison, uuid: uuid, source: source)
            } else {
                checked[uuid] = (signature, .unavailable)
            }
        } catch is CancellationError {
            checked[uuid] = nil
        } catch let error as URLError where error.code == .cancelled {
            checked[uuid] = nil
        } catch {
            checked[uuid] = (signature, .unavailable)
        }
    }

    /// Takes what a comparison found: nothing to change is as good as sent.
    func record(_ comparison: GarminComparison, uuid: String, source: GarminSource) {
        if comparison.proposal.isEmpty {
            markSynced(uuid: uuid, source: source)
        } else {
            checked[uuid] = (source.signature, .needsSync)
        }
    }

    func markSynced(uuid: String, source: GarminSource) {
        checked[uuid] = nil
        synced[uuid] = source.signature
        defaults.set(synced, forKey: Self.storageKey)
    }
}
