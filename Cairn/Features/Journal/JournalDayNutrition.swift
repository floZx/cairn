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
    /// Aller à la journée des repas.
    ///
    /// Le récap des sorties menait à la sortie depuis toujours ; celui-ci ne
    /// menait nulle part, et deux blocs voisins qui ne se comportent pas
    /// pareil se lisent comme un des deux cassé. Signalé.
    let onSelectDay: (DateKey) -> Void
    /// Aller au poids.
    ///
    /// Une destination à part, et pas la journée des repas où le commentaire
    /// se modifie pourtant : une carte qui affiche « 71,2 kg » annonce le
    /// poids, et c'est là qu'on s'attend à arriver. Signalé aussi.
    let onSelectWeight: () -> Void

    /// Read against `JournalDetailView.noteSize` — the note this pane is for,
    /// at 15. The same pair as the activities' recap, so the two blocks under
    /// a note rank equally and neither shouts over the other.
    private static let noteSize: CGFloat = 14
    private static let headingSize: CGFloat = 13

    @Query private var mealNotes: [MealNote]
    @Query private var weights: [WeightEntry]

    init(
        date: DateKey,
        onSelectDay: @escaping (DateKey) -> Void,
        onSelectWeight: @escaping () -> Void
    ) {
        self.date = date
        self.onSelectDay = onSelectDay
        self.onSelectWeight = onSelectWeight
        let raw = date.raw
        _mealNotes = Query(filter: #Predicate<MealNote> { $0.dateKeyRaw == raw })
        _weights = Query(filter: #Predicate<WeightEntry> { $0.dateKeyRaw == raw })
    }

    /// The meals that said something, in the order they are eaten.
    ///
    /// Sorted here and not in the query: the order lives on the slot, across a
    /// relationship, and a `SortDescriptor` cannot reach through one. Static
    /// and taking its data as a parameter — like `JournalDayActivities.note(of:)`
    /// and `figures(...)` — so the triage rule is reachable from a test without
    /// standing up a `@Query`.
    static func spokenMeals(among notes: [MealNote]) -> [MealNote] {
        notes
            .filter { !isBlank($0.note) }
            .sorted {
                ($0.mealSlot?.sortOrder ?? .max) < ($1.mealSlot?.sortOrder ?? .max)
            }
    }

    /// The day's weigh-in, and only when it carries a comment: the figure
    /// alone belongs to the food journal, which shows it already.
    static func spokenWeight(among weights: [WeightEntry]) -> WeightEntry? {
        weights.first { !isBlank($0.note) }
    }

    private static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The meal's own note, trimmed of the leading and trailing blanks that
    /// triage by `isBlank` but that `MarkdownText` does not: an import from
    /// suivinut can start on a stray newline, and a card should not open on
    /// a blank line for it. The Markdown itself is left alone — trimming
    /// inside a line would be interpreting it, which is `MarkdownText`'s job.
    static func note(of note: MealNote) -> String {
        note.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The weigh-in's own comment, trimmed the same way.
    /// `spokenWeight(among:)` already keeps only entries with a comment, so
    /// this never has to stand in for a missing one.
    static func note(of entry: WeightEntry) -> String {
        (entry.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name a meal note is announced by. Never empty: `mealSlot` is
    /// optional in the model, so this must answer something even when a note
    /// has none, and a blank title line would puzzle more than a generic
    /// word.
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
        let spokenMeals = Self.spokenMeals(among: mealNotes)
        let spokenWeight = Self.spokenWeight(among: weights)
        if !spokenMeals.isEmpty || spokenWeight != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alimentation du jour")
                    .font(.system(size: Self.headingSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(spokenMeals) { note in
                    block(Self.label(for: note), Self.note(of: note), aide: "Alimentation") {
                        onSelectDay(date)
                    }
                }
                if let spokenWeight {
                    block(
                        Self.weightLine(spokenWeight), Self.note(of: spokenWeight),
                        aide: "Poids", onOuvrir: onSelectWeight
                    )
                }
            }
        }
    }

    /// One card: what it is, then what was written about it.
    ///
    /// The heading is a button and the note is rendered — the meal's name and
    /// the weight are labels, the note is prose somebody wrote, and it is read
    /// here exactly as it is read in its own pane: Markdown, without the `#`
    /// of a tag.
    ///
    /// Le titre porte le clic, la note reste sélectionnable : c'est le partage
    /// exact du récap des sorties, et pour la même raison — un texte
    /// sélectionnable prend le clic pour lui, si bien qu'une carte entièrement
    /// cliquable ne le serait qu'entre les mots.
    private func block(
        _ heading: String, _ note: String, aide: String, onOuvrir: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onOuvrir) {
                Text(heading)
                    .font(.system(size: Self.headingSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Ouvrir dans \(aide)")
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
