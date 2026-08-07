import Foundation

/// What the editing sheet holds, and everything it knows how to decide.
///
/// A value type with no view in sight, which is what makes the interesting part
/// testable: which fields the user actually changed, whether the whole is
/// coherent, and what to write back. The sheet becomes a set of bindings.
///
/// Units are the user's — kilometres and minutes — and the conversion to the
/// model's metres and seconds happens here, so no view has to know about it.
struct ActivityDraft: Equatable {
    var name: String
    var sport: SportType
    var startLocalDate: Date
    var distanceKm: Double
    var movingMinutes: Double
    var elevationGain: Double
    var notes: String
    var isCommute: Bool
    var isTrainer: Bool

    init(_ activity: Activity) {
        name = activity.name
        sport = activity.sportType
        startLocalDate = activity.startLocalDate
        distanceKm = activity.distance / 1000
        movingMinutes = Double(activity.movingTime) / 60
        elevationGain = activity.totalElevationGain
        notes = activity.activityDescription ?? ""
        isCommute = activity.isCommute
        isTrainer = activity.isTrainer
    }

    /// An empty draft for a session that never went through a watch.
    init(startingOn date: Date) {
        name = ""
        sport = .workout
        startLocalDate = date
        distanceKm = 0
        movingMinutes = 0
        elevationGain = 0
        notes = ""
        isCommute = false
        isTrainer = false
    }

    /// Why this cannot be saved, or nil if it can.
    ///
    /// A message rather than a Bool so the sheet can say what is missing instead
    /// of merely greying out a button.
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Le nom ne peut pas être vide."
        }
        if movingMinutes <= 0 {
            return "La durée doit être supérieure à zéro."
        }
        if distanceKm < 0 || elevationGain < 0 {
            return "Distance et dénivelé ne peuvent pas être négatifs."
        }
        return nil
    }

    /// The fields whose value differs from the activity's.
    ///
    /// Compared field by field rather than assumed from what the sheet touched:
    /// typing in a field and undoing it must not count as an edit.
    func changedFields(comparedTo activity: Activity) -> Set<ActivityField> {
        var changed: Set<ActivityField> = []
        let original = ActivityDraft(activity)
        if name != original.name { changed.insert(.name) }
        if sport != original.sport { changed.insert(.sportType) }
        if startLocalDate != original.startLocalDate { changed.insert(.startDate) }
        if distanceKm != original.distanceKm { changed.insert(.distance) }
        if movingMinutes != original.movingMinutes { changed.insert(.movingTime) }
        if elevationGain != original.elevationGain {
            changed.insert(.totalElevationGain)
        }
        if notes != original.notes { changed.insert(.notes) }
        if isCommute != original.isCommute { changed.insert(.isCommute) }
        if isTrainer != original.isTrainer { changed.insert(.isTrainer) }
        return changed
    }

    /// Writes the values, and claims only the fields that moved.
    func apply(to activity: Activity) {
        let changed = changedFields(comparedTo: activity)
        write(to: activity)
        // Only for what the sync could otherwise overwrite. On a local activity
        // every field is the user's, so a set of claims would be noise.
        if activity.source.isSynced {
            activity.markEdited(changed)
        }
    }

    /// A brand-new local activity.
    func makeActivity() -> Activity {
        let activity = Activity(stravaID: 0, name: name, sportType: sport)
        activity.source = .manual
        write(to: activity)
        return activity
    }

    private func write(to activity: Activity) {
        activity.name = name.trimmingCharacters(in: .whitespaces)
        activity.sportType = sport
        activity.startLocalDate = startLocalDate
        // Both, because every sort and filter reads `startDate` while the user
        // only ever sees the local one.
        activity.startDate = startLocalDate
        activity.distance = distanceKm * 1000
        activity.movingTime = Int(movingMinutes * 60)
        // Elapsed time is not editable and would otherwise stay below moving
        // time, which reads as a bug in the detail pane.
        activity.elapsedTime = max(activity.elapsedTime, activity.movingTime)
        activity.totalElevationGain = elevationGain
        activity.activityDescription = notes.isEmpty ? nil : notes
        activity.isCommute = isCommute
        activity.isTrainer = isTrainer
    }
}
