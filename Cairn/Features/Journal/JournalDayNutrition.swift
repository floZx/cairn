import SwiftUI
import SwiftData

/// What the day's food journal said in words — a meal's note, a weigh-in's
/// comment — beside the note written about the day itself.
///
/// A sister of `JournalDayActivities`, and silent on the same terms: a heading
/// over an empty list says less than no heading. Most days have neither.
///
/// Its own queries rather than a list handed down from `RootView`, for the
/// reason given there: the note's pane rebuilds on every keystroke, and these
/// filter on `dateKeyRaw`, a string equality, where the outings needed a range
/// of instants.
struct JournalDayNutrition: View {
    let date: DateKey

    /// Read against `JournalDetailView.noteSize` — the note this pane is for,
    /// at 15. The same pair as the activities' recap, so the two blocks under
    /// a note rank equally and neither shouts over the other.
    private static let noteSize: CGFloat = 14
    private static let headingSize: CGFloat = 13

    @Query private var mealNotes: [MealNote]
    @Query private var weights: [WeightEntry]

    init(date: DateKey) {
        self.date = date
        let raw = date.raw
        _mealNotes = Query(filter: #Predicate<MealNote> { $0.dateKeyRaw == raw })
        _weights = Query(filter: #Predicate<WeightEntry> { $0.dateKeyRaw == raw })
    }

    /// The meals that said something, in the order they are eaten.
    ///
    /// Sorted here and not in the query: the order lives on the slot, across a
    /// relationship, and a `SortDescriptor` cannot reach through one.
    private var spokenMeals: [MealNote] {
        mealNotes
            .filter { !Self.isBlank($0.note) }
            .sorted {
                ($0.mealSlot?.sortOrder ?? .max) < ($1.mealSlot?.sortOrder ?? .max)
            }
    }

    /// The day's weigh-in, and only when it carries a comment: the figure
    /// alone belongs to the food journal, which shows it already.
    private var spokenWeight: WeightEntry? {
        weights.first { !Self.isBlank($0.note) }
    }

    private static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The name a meal note is announced by. Never empty: deleting a meal in
    /// the settings leaves its notes behind, and a nameless chip would puzzle
    /// more than a generic word.
    static func label(for note: MealNote) -> String {
        let name = note.mealSlot?.name ?? ""
        return name.isEmpty ? "Repas" : name
    }

    /// The weight, written the way it is written everywhere else in the app:
    /// a comma, and no trailing zero on a round figure.
    static func weightLine(_ entry: WeightEntry) -> String {
        "\(Format.typedNumber(entry.weightKg)) kg"
    }

    var body: some View {
        if !spokenMeals.isEmpty || spokenWeight != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alimentation du jour")
                    .font(.system(size: Self.headingSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(spokenMeals) { note in
                    block(Self.label(for: note), note.note)
                }
                if let spokenWeight {
                    block(Self.weightLine(spokenWeight), spokenWeight.note ?? "")
                }
            }
        }
    }

    /// One card: what it is, then what was written about it.
    ///
    /// The heading is a `Text` and the note is rendered — the meal's name and
    /// the weight are labels, the note is prose somebody wrote, and it is read
    /// here exactly as it is read in its own pane: Markdown, without the `#`
    /// of a tag.
    private func block(_ heading: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading)
                .font(.system(size: Self.headingSize))
                .foregroundStyle(.secondary)
            MarkdownText(
                markdown: note, baseSize: Self.noteSize, hidesTagHashes: true
            )
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 5))
    }
}
