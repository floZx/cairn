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
    /// Nil means "no particular type", which is a value the user can choose —
    /// not merely the absence of one.
    var workoutLabel: ActivityLabel?

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
        workoutLabel = activity.workoutLabel
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
        workoutLabel = nil
    }

    /// The name as it will actually be saved.
    ///
    /// A property of the draft, not a one-off call at a single call site, and
    /// used on *both* operands wherever names are compared — `changedFields`
    /// included, via `original.trimmedName`. Trimming one side only moves the
    /// same defect instead of fixing it: an activity imported straight from
    /// Strava's title is never trimmed at the source, so comparing a trimmed
    /// draft to `activity.name` untouched would mark `.name` on a save that
    /// only ever touched the distance. Newlines count as whitespace too: a
    /// name reduced to one would otherwise read as non-empty.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Why this cannot be saved, or nil if it can.
    ///
    /// A message rather than a Bool so the sheet can say what is missing instead
    /// of merely greying out a button.
    var validationMessage: String? {
        if trimmedName.isEmpty {
            return "Le nom ne peut pas être vide."
        }
        // NaN or infinite values pass every comparison below without tripping
        // it — `NaN <= 0` and `NaN < 0` are both false — and would otherwise
        // reach `Int(...)` in `write(to:)`, which traps rather than throwing.
        if !movingMinutes.isFinite || !distanceKm.isFinite || !elevationGain.isFinite {
            return "Durée, distance et dénivelé doivent être des nombres valides."
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
        if trimmedName != original.trimmedName { changed.insert(.name) }
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
        if workoutLabel != original.workoutLabel { changed.insert(.workoutLabel) }
        return changed
    }

    /// Writes the values, and claims only the fields that moved.
    ///
    /// Mutates `activity` in place and returns nothing: the caller still owns
    /// `context.save()`. Skipping it leaves the screen showing the edit with
    /// nothing written to disk — the exact silent loss this project exists to
    /// prevent, just triggered from the other write path.
    func apply(to activity: Activity) {
        let changed = changedFields(comparedTo: activity)
        write(to: activity)
        // Only for what the sync could otherwise overwrite. On a local activity
        // every field is the user's, so a set of claims would be noise.
        if activity.source.isSynced {
            activity.markEdited(changed)
        }
    }

    /// A brand-new local activity, not yet inserted into any context: the
    /// caller must both `context.insert` it and `context.save()`, since only
    /// the caller holds the `ModelContext`.
    func makeActivity() -> Activity {
        let activity = Activity(stravaID: 0, name: name, sportType: sport)
        activity.source = .manual
        // `Activity.labels` reads `isManual`, not `source`: without this a
        // hand-entered session would carry no badge at all.
        activity.isManual = true
        write(to: activity)
        return activity
    }

    private func write(to activity: Activity) {
        activity.name = trimmedName
        activity.sportType = sport
        // `startDate` is the UTC instant, `startLocalDate` the wall time where
        // the activity happened. Assigning one to the other silently drops the
        // offset — two hours, for an outing recorded in UTC+2 — on a value the
        // list sorts by, the period filter bounds with, and the sync cursor
        // rewinds to. Shifting by the delta keeps the offset whatever it was,
        // and this reduces to a plain assignment for a brand-new activity,
        // whose `startDate` and `startLocalDate` start out equal.
        activity.startDate = activity.startDate.addingTimeInterval(
            startLocalDate.timeIntervalSince(activity.startLocalDate)
        )
        activity.startLocalDate = startLocalDate

        let previousDistance = activity.distance
        let previousMovingTime = activity.movingTime
        activity.distance = distanceKm * 1000
        // Rounded rather than truncated: `Int(_:)` on a value one
        // floating-point epsilon below the intended second — an artefact of
        // the km/minutes round trip, not a real edit — would otherwise lose a
        // second on every save, silently, since the field stays unmarked.
        activity.movingTime = Int((movingMinutes * 60).rounded())
        // Elapsed time is not editable and would otherwise stay below moving
        // time, which reads as a bug in the detail pane.
        activity.elapsedTime = max(activity.elapsedTime, activity.movingTime)
        // A stored column, not a computed one, so it stays sortable and reads
        // straight off the model everywhere else — but that means it goes
        // stale the moment distance or moving time change, exactly like
        // `elapsedTime`. Recomputed only when one of them actually moved, so
        // an unrelated edit (or a brand-new manual entry with neither) leaves
        // it alone.
        if activity.distance != previousDistance || activity.movingTime != previousMovingTime {
            activity.averageSpeed = activity.movingTime > 0
                ? activity.distance / Double(activity.movingTime)
                : 0
        }
        activity.totalElevationGain = elevationGain
        activity.activityDescription = notes.isEmpty ? nil : notes
        activity.isCommute = isCommute
        activity.isTrainer = isTrainer
        activity.workoutLabel = workoutLabel
    }
}
