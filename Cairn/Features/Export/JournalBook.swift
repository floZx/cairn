import Foundation
import SwiftData

/// Everything an exported book holds, gathered in one pure pass.
///
/// A value and not a view model: what a book contains is a decision worth
/// testing on its own — which days earn a section, in what order, with what
/// totals — and none of it needs a window to be true. The HTML, the maps and
/// the PDF all come later, from this.
struct JournalBook: Equatable {
    struct Meal: Equatable {
        var name: String
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var note: String?
    }

    struct Day: Equatable {
        var date: DateKey
        var note: String
        var tags: [JournalTag]
        var activities: [Activity]
        var meals: [Meal]
        var weightKg: Double?
        var weightNote: String?
    }

    struct Totals {
        var activityCount: Int
        var distance: Double
        var elevation: Double
        var movingTime: Int
        var bySport: [(sport: SportType, count: Int, distance: Double)]
        var firstWeightKg: Double?
        var lastWeightKg: Double?
    }

    var from: DateKey
    var to: DateKey
    var days: [Day]
    var totals: Totals

    /// - Parameters are the store's own arrays, filtered by the caller only for
    ///   convenience: the period is applied here, so a caller that hands over
    ///   its whole library gets the same book as one that pre-filtered.
    static func build(
        from: DateKey, to: DateKey, notes: [JournalNote], activities: [Activity],
        entries: [FoodEntry], slots: [MealSlot], mealNotes: [MealNote],
        weights: [WeightEntry]
    ) -> JournalBook {
        func spoken(_ text: String?) -> String? {
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : text
        }
        func inRange(_ date: DateKey) -> Bool { date >= from && date <= to }

        // The day an outing belongs to is its instant read in this Mac's
        // calendar — `JournalDaySources`' rule. A book and a list that filed
        // the same outing under two different days would be a defect on their
        // own.
        var activitiesByDay: [DateKey: [Activity]] = [:]
        for activity in activities.sorted(by: { $0.startDate < $1.startDate }) {
            let date = DateKey(activity.startDate)
            guard inRange(date) else { continue }
            activitiesByDay[date, default: []].append(activity)
        }

        var notesByDay: [DateKey: JournalNote] = [:]
        for note in notes where inRange(note.date) && spoken(note.text) != nil {
            notesByDay[note.date] = note
        }

        var weightsByDay: [DateKey: WeightEntry] = [:]
        for weight in weights {
            guard let date = weight.dateKey, inRange(date) else { continue }
            weightsByDay[date] = weight
        }

        // Every day any source touches, before the rule below decides which of
        // them earns a section.
        var touched = Set(notesByDay.keys)
            .union(activitiesByDay.keys)
            .union(weightsByDay.keys)
        for note in mealNotes {
            guard let date = note.dateKey, inRange(date),
                  spoken(note.note) != nil else { continue }
            touched.insert(date)
        }
        for entry in entries {
            guard let date = DateKey(raw: entry.dateKeyRaw), inRange(date) else { continue }
            touched.insert(date)
        }

        let orderedSlots = slots.sorted { $0.sortOrder < $1.sortOrder }
        var mealsByDay: [DateKey: [Meal]] = [:]
        var wroteAboutAMeal: Set<DateKey> = []
        for date in touched {
            let dayEntries = entries.filter { $0.dateKeyRaw == date.raw }
            var meals: [Meal] = []
            for slot in orderedSlots {
                let rows = dayEntries.filter {
                    $0.mealSlot?.persistentModelID == slot.persistentModelID
                }
                let note = spoken(
                    mealNotes.first {
                        $0.dateKeyRaw == date.raw
                            && $0.mealSlot?.persistentModelID == slot.persistentModelID
                    }?.note
                )
                guard !rows.isEmpty || note != nil else { continue }
                if note != nil { wroteAboutAMeal.insert(date) }
                // The sum the day screen already computes, reached rather than
                // written a second time.
                let macros = rows.map(Macros.init(of:)).reduce(.zero, +)
                meals.append(
                    Meal(
                        name: slot.name, kcal: macros.kcal, protein: macros.protein,
                        carbs: macros.carbs, fat: macros.fat, note: note
                    )
                )
            }
            if !meals.isEmpty { mealsByDay[date] = meals }
        }

        var days: [Day] = []
        for date in touched.sorted() {
            let weight = weightsByDay[date]
            // Logging food is not writing about a day — the journal's own rule.
            // A weigh-in is the one source that earns its place as a figure,
            // because a weight is a fact about the day and not a by-product of
            // having eaten.
            let earnsASection = notesByDay[date] != nil
                || activitiesByDay[date] != nil
                || weight != nil
                || wroteAboutAMeal.contains(date)
            guard earnsASection else { continue }
            let note = notesByDay[date]
            days.append(
                Day(
                    date: date,
                    note: note?.text ?? "",
                    tags: note.map { $0.tags.sorted() } ?? [],
                    activities: activitiesByDay[date] ?? [],
                    meals: mealsByDay[date] ?? [],
                    weightKg: weight?.weightKg,
                    weightNote: spoken(weight?.note)
                )
            )
        }

        return JournalBook(
            from: from, to: to, days: days,
            totals: totals(of: days, weights: weightsByDay)
        )
    }

    /// What the period weighed, for the cover.
    ///
    /// Counted over the days the book kept, not over the raw arrays: a cover
    /// announcing twelve outings above a book showing eleven would be a lie the
    /// reader could check.
    private static func totals(
        of days: [Day], weights: [DateKey: WeightEntry]
    ) -> Totals {
        let outings = days.flatMap(\.activities)
        var bySport: [SportType: (count: Int, distance: Double)] = [:]
        for activity in outings {
            let sport = activity.sportType
            let tally = bySport[sport] ?? (0, 0)
            bySport[sport] = (tally.count + 1, tally.distance + activity.distance)
        }
        let ordered = bySport
            .map { (sport: $0.key, count: $0.value.count, distance: $0.value.distance) }
            // Most travelled first: that is what the period was spent on.
            .sorted { $0.distance > $1.distance }

        let weighed = weights.keys.sorted()
        return Totals(
            activityCount: outings.count,
            distance: outings.reduce(0) { $0 + $1.distance },
            elevation: outings.reduce(0) { $0 + $1.totalElevationGain },
            movingTime: outings.reduce(0) { $0 + $1.movingTime },
            bySport: ordered,
            firstWeightKg: weighed.first.flatMap { weights[$0]?.weightKg },
            lastWeightKg: weighed.last.flatMap { weights[$0]?.weightKg }
        )
    }
}

/// Written by hand because `bySport` is an array of tuples, which Swift will
/// not synthesise a comparison for.
extension JournalBook.Totals: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.activityCount == rhs.activityCount
            && lhs.distance == rhs.distance
            && lhs.elevation == rhs.elevation
            && lhs.movingTime == rhs.movingTime
            && lhs.firstWeightKg == rhs.firstWeightKg
            && lhs.lastWeightKg == rhs.lastWeightKg
            && lhs.bySport.count == rhs.bySport.count
            && zip(lhs.bySport, rhs.bySport).allSatisfy {
                $0.sport == $1.sport && $0.count == $1.count
                    && $0.distance == $1.distance
            }
    }
}
