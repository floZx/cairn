import Foundation
import Observation

/// Sends a correction made in Cairn's editor on to Strava and Garmin Connect:
/// a new title, other gear.
///
/// Automatic, and those two only. Everything else the editor touches stays in
/// Cairn: the description here carries the Strava private note merged into
/// it, and sending that to Strava would make it public.
///
/// A failure doesn't undo the edit — Cairn has it, and that is what counts
/// here — but it is kept against the activity until the next attempt, so the
/// pane can say which service still shows the old value.
@MainActor
@Observable
final class EditPropagator {
    enum Edit: Sendable {
        case name
        /// The gear's Strava id, nil for none.
        case gear(stravaGearID: String?)
    }

    private let strava: StravaClient
    private let garmin: GarminClient
    private let garminSync: GarminSyncTracker

    /// Activity uuid → what went wrong, one line per service.
    private(set) var failures: [String: String] = [:]
    /// What the failure was about, so a retry sends the same thing.
    private(set) var failedEdits: [String: [Edit]] = [:]

    init(strava: StravaClient, garmin: GarminClient, garminSync: GarminSyncTracker) {
        self.strava = strava
        self.garmin = garmin
        self.garminSync = garminSync
    }

    /// - Parameters:
    ///   - stravaID: the activity on Strava, nil for one that only exists here.
    func propagate(
        _ edits: [Edit], uuid: String, stravaID: Int64?, source: GarminSource,
        toStrava: Bool, toGarmin: Bool
    ) async {
        let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let edits = edits.filter { edit in
            if case .name = edit { return !name.isEmpty }
            return true
        }
        guard !edits.isEmpty else { return }
        failures[uuid] = nil
        failedEdits[uuid] = nil
        var problems: [String] = []
        // Held from the start, Strava's turn included: the pane opens on the
        // edited activity at once, and its own check would otherwise race
        // this one to Garmin.
        let hold = toGarmin ? garminSync.hold(uuid: uuid, source: source) : nil
        defer { if let hold { garminSync.release(uuid: uuid, token: hold) } }

        if toStrava, let stravaID {
            do {
                for edit in edits {
                    switch edit {
                    case .name:
                        try await strava.updateName(id: stravaID, name: name)
                    case let .gear(gearID):
                        try await strava.updateGear(id: stravaID, gearID: gearID)
                    }
                }
            } catch {
                problems.append("Strava : \(error.localizedDescription)")
            }
        }

        if toGarmin {
            do {
                // Found by start, distance and duration — never by the field
                // being sent, which is precisely what differs.
                if let before = try await garmin.compare(source) {
                    for edit in edits {
                        try await send(edit, name: name, to: before)
                    }
                    // Read back, so the pane's Garmin status reflects the
                    // change rather than what Garmin said a second ago.
                    if let after = try await garmin.compare(source) {
                        garminSync.record(after, uuid: uuid, source: source)
                    }
                }
            } catch {
                problems.append("Garmin : \(error.localizedDescription)")
            }
        }

        if !problems.isEmpty {
            failures[uuid] = problems.joined(separator: "\n")
            failedEdits[uuid] = edits
        }
    }

    /// Only the edited fields: the other differences stay for the Garmin sheet,
    /// where they are shown before being sent.
    private func send(_ edit: Edit, name: String, to comparison: GarminComparison) async throws {
        let id = comparison.activity.id
        switch edit {
        case .name:
            guard comparison.activity.name.trimmingCharacters(in: .whitespacesAndNewlines) != name
            else { return }
            try await garmin.updateActivity(id: id, name: name, description: nil, type: nil)
        case .gear:
            // No Garmin gear by that name, or gear removed in Cairn: Garmin's
            // is left as it is — a pair of shoes can't be matched to nothing.
            guard let wanted = comparison.proposal.gearUUIDs else { return }
            try await garmin.setGear(wanted, current: comparison.currentGear, activityID: id)
        }
    }
}
