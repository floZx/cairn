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
    /// What each day did, whether or not anyone wrote about it.
    ///
    /// Read from every outing rather than from the ones carrying a note: a day
    /// that has a vault note and a silent run still ran, and the glyph is the
    /// only thing in the row that would say so.
    ///
    /// Days with no mark are simply absent — a dictionary of empty marks would
    /// be a dictionary of nothing.
    /// Les seuls jours **nommés** par quelque chose, sans rien construire de
    /// plus.
    ///
    /// La barre latérale ne demande que ça : un compte pour sa pastille, et
    /// des dates pour les points de son calendrier. Elle recevait pourtant la
    /// fusion complète — laquelle trie toutes les sorties et traverse les
    /// photos de chacune —, et elle la recevait sur **tous** les écrans, à
    /// chaque évaluation du corps de la vue racine. Le profileur en faisait
    /// 56 % du temps du fil principal.
    ///
    /// Ici : une lecture de propriété par ligne, aucun tri, aucune photo.
    static func dayKeys(
        notes: [JournalFileNote], activities: [Activity],
        mealNotes: [MealNote], weights: [WeightEntry]
    ) -> Set<String> {
        libraryDayKeys(activities: activities, mealNotes: mealNotes, weights: weights)
            .union(notes.map(\.date.raw))
    }

    /// La même chose sans le carnet : ce que la bibliothèque seule nomme.
    ///
    /// La coupure sert `JournalLibraryCache` — cette moitié-ci ne bouge qu'à
    /// l'écriture, quand celle du carnet bouge à chaque frappe. Les deux se
    /// réunissent à la lecture, où les notes se comptent sur les doigts.
    static func libraryDayKeys(
        activities: [Activity], mealNotes: [MealNote], weights: [WeightEntry]
    ) -> Set<String> {
        var jours: Set<String> = []
        for activity in activities { jours.insert(DateKey(activity.startDate).raw) }
        for weight in weights where !isBlank(weight.note) {
            if let date = weight.dateKey { jours.insert(date.raw) }
        }
        // Les pesées sans un mot marquent quand même leur jour : c'est la
        // règle de `marks`, et la liste les montre.
        for weight in weights { if let date = weight.dateKey { jours.insert(date.raw) } }
        for note in mealNotes where !isBlank(note.note) {
            if let date = note.dateKey { jours.insert(date.raw) }
        }
        return jours
    }

    private static func isBlank(_ texte: String?) -> Bool {
        (texte ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func marks(
        activities: [Activity], weights: [WeightEntry]
    ) -> [DateKey: JournalDay.Marks] {
        var marks: [DateKey: JournalDay.Marks] = [:]
        // La date est lue **une fois** par sortie, puis on trie ces couples.
        //
        // Le comparateur lisait `startDate` à chaque comparaison, soit deux
        // accès SwiftData par paire : sur huit cents sorties, le profileur
        // attribuait 28 % du temps du fil principal à ce seul accesseur, et
        // 38 % au tri qui l'appelait. Or ce tri tourne à chaque évaluation du
        // corps de la vue racine — donc à chaque touche frappée dans le
        // journal, qui enregistre au fil de l'écriture.
        let parDate = activities
            .map { (date: $0.startDate, sortie: $0) }
            .sorted { $0.date < $1.date }
        for (brute, activity) in parDate {
            let date = DateKey(brute)
            var day = marks[date] ?? .none
            if !day.sports.contains(activity.sportType) {
                day.sports.append(activity.sportType)
            }
            // The pictures an outing carries belong to the day as much as the
            // ones typed into its note: both say what it looked like, and the
            // row shows them in one strip.
            day.photoIDs += activity.orderedPhotos.map(\.persistentModelID)
            marks[date] = day
        }
        for weight in weights {
            guard let date = weight.dateKey else { continue }
            var day = marks[date] ?? .none
            day.weighed = true
            marks[date] = day
        }
        return marks
    }

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
