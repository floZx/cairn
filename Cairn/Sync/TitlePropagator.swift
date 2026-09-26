import Foundation
import Observation

/// Sends a title changed in Cairn's editor on to Strava and Garmin Connect.
///
/// Automatic, and the title only. Everything else the editor touches stays in
/// Cairn: the description here carries the Strava private note merged into
/// it, and sending that to Strava would make it public.
///
/// A failure doesn't undo the edit — Cairn has it, and that is what counts
/// here — but it is kept against the activity until the next attempt, so the
/// pane can say which service still shows the old title.
@MainActor
@Observable
final class TitlePropagator {
    private let strava: StravaClient
    private let garmin: GarminClient
    private let garminSync: GarminSyncTracker

    /// Activity uuid → what went wrong, one line per service.
    private(set) var failures: [String: String] = [:]

    init(strava: StravaClient, garmin: GarminClient, garminSync: GarminSyncTracker) {
        self.strava = strava
        self.garmin = garmin
        self.garminSync = garminSync
    }

    /// - Parameters:
    ///   - stravaID: the activity on Strava, nil for one that only exists here.
    func propagate(
        uuid: String, stravaID: Int64?, source: GarminSource,
        toStrava: Bool, toGarmin: Bool
    ) async {
        let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        failures[uuid] = nil
        var problems: [String] = []
        // Held from the start, Strava's turn included: the pane opens on the
        // edited activity at once, and its own check would otherwise race
        // this one to Garmin.
        let hold = toGarmin ? garminSync.hold(uuid: uuid, source: source) : nil
        defer { if let hold { garminSync.release(uuid: uuid, token: hold) } }

        if toStrava, let stravaID {
            do {
                try await strava.updateName(id: stravaID, name: name)
            } catch {
                problems.append("Strava : \(error.localizedDescription)")
            }
        }

        if toGarmin {
            do {
                // Found by start, distance and duration — never by the title,
                // which is precisely what differs.
                if let before = try await garmin.compare(source) {
                    if before.activity.name.trimmingCharacters(in: .whitespacesAndNewlines) != name {
                        try await garmin.updateActivity(
                            id: before.activity.id, name: name, description: nil, type: nil
                        )
                    }
                    // Read back, so the pane's Garmin status reflects the
                    // rename rather than what Garmin said a second ago.
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
        }
    }
}
