import Foundation

/// Everything written about a day outside the vault, gathered per day.
///
/// A function and not a view's private helper: the collection is the rule that
/// decides which days the journal lists at all, and a rule worth stating is a
/// rule worth testing. `RootView` holds the queries; this holds the meaning.
@MainActor
enum JournalDaySources {
    /// Blank texts never enter: a meal note opened and closed without a word
    /// must not make a day appear, and a weigh-in is a figure, not a sentence.
    /// The weigh-in's own comment is a sentence, and does count.
    ///
    /// - Returns: the texts of a day, in the order the day was lived — the
    ///   outings first, then the meals in the order they are eaten, the
    ///   weigh-in last. `JournalDay.summary` takes the first of them for a day
    ///   with no file, so this order is what a row reads.
    static func elsewhereNotes(
        activities: [Activity], mealNotes: [MealNote], weights: [WeightEntry]
    ) -> [DateKey: [String]] {
        var byDay: [DateKey: [String]] = [:]

        func add(_ text: String?, to date: DateKey) {
            guard let text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            byDay[date, default: []].append(text)
        }

        // The day an outing belongs to is `DateKey` of its instant in this
        // Mac's calendar — the same rule `JournalDayActivities` filters the
        // recap by, so a day's row and a day's pane cannot disagree about
        // which outings are its own. Meals and weigh-ins need no such rule:
        // they are filed under a day, never under an instant.
        for activity in activities.sorted(by: { $0.startDate < $1.startDate }) {
            add(activity.activityDescription, to: DateKey(activity.startDate))
        }
        for meal in mealNotes.sorted(by: {
            ($0.mealSlot?.sortOrder ?? .max) < ($1.mealSlot?.sortOrder ?? .max)
        }) {
            guard let date = meal.dateKey else { continue }
            add(meal.note, to: date)
        }
        for weight in weights {
            guard let date = weight.dateKey else { continue }
            add(weight.note, to: date)
        }
        return byDay
    }
}
