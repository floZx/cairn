import Foundation

/// A day of the journal, whatever was written about it and wherever.
///
/// The list used to be the folder's files and nothing else, so a day one had
/// written about only on the outing itself — "jambes lourdes, vent de face" in
/// a Strava note — was in the journal but nowhere in the journal's list, and no
/// search would find it. This is the two sources read as one memory: the day's
/// own note from the vault, and what the day's activities carry.
///
/// The vault stays the only thing Cairn *writes*. An activity's note is read
/// here and edited where it lives, in the activity itself.
struct JournalDay: Identifiable, Equatable, Sendable {
    let date: DateKey
    /// The vault's file for this day. Its text is empty when there is none —
    /// which is exactly the note that starts existing when one types into it.
    let note: JournalNote
    /// What the day's outings say, in the order they happened. Only the ones
    /// that say something.
    let activityNotes: [String]

    var id: DateKey { date }

    init(date: DateKey, note: JournalNote? = nil, activityNotes: [String] = []) {
        self.date = date
        self.note = note ?? JournalNote(date: date, text: "")
        self.activityNotes = activityNotes
    }

    /// The tags of both sources together.
    ///
    /// An activity's note is a database field rather than a file in the vault,
    /// but the person writing `#Sam` in one meant the same thing as in the
    /// other, and a tag list that answered only for half of them would be a
    /// tag list one cannot trust.
    var tags: Set<JournalTag> {
        activityNotes.reduce(into: note.tags) { all, text in
            all.formUnion(JournalTagScanner.tags(in: text))
        }
    }

    /// The line that stands for the day when nothing is being searched for.
    ///
    /// The day's own note first: it is the one written *about* the day, where
    /// an outing's note is written about the outing. A day that exists only
    /// because of an outing falls back to what that outing said.
    var summary: String {
        note.isEmpty
            ? (activityNotes.first.map { JournalNote(date: date, text: $0).summary } ?? "")
            : note.summary
    }

    func matches(query: String) -> Bool {
        note.matches(query: query)
            || activityNotes.contains { JournalNote.matches($0, query: query) }
    }

    /// The passage that answered the search, from whichever text answered it.
    func excerpt(matching query: String) -> String? {
        note.excerpt(matching: query)
            ?? activityNotes.lazy
                .compactMap { JournalNote.excerpt(of: $0, matching: query) }
                .first
    }

    func has(_ required: Set<JournalTag>) -> Bool {
        required.isSubset(of: tags)
    }

    /// The two sources merged, newest first.
    ///
    /// `notes` wins on identity: a day with a file keeps that file's note and
    /// gains its outings' notes beside it. **Every note the store lists is
    /// kept, empty or not** — the store holds an empty row on purpose for the
    /// day being written, and dropping it here would take the pane, and the
    /// caret in it, away mid-sentence.
    ///
    /// A day that exists only because of an outing is added only when that
    /// outing actually said something: a day trained on in silence is not a
    /// journal entry.
    static func merge(
        notes: [JournalNote], activityNotes: [DateKey: [String]]
    ) -> [JournalDay] {
        var days: [JournalDay] = notes.map {
            JournalDay(
                date: $0.date, note: $0,
                activityNotes: spoken(activityNotes[$0.date])
            )
        }
        let written = Set(notes.map(\.date))
        for (date, texts) in activityNotes where !written.contains(date) {
            let said = spoken(texts)
            guard !said.isEmpty else { continue }
            days.append(JournalDay(date: date, activityNotes: said))
        }
        return days.sorted { $0.date > $1.date }
    }

    private static func spoken(_ texts: [String]?) -> [String] {
        (texts ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Search text and ticked tags together; the order `merge` produced.
    static func filter(
        _ days: [JournalDay], query: String, tags: Set<JournalTag>
    ) -> [JournalDay] {
        days.filter { $0.has(tags) && $0.matches(query: query) }
    }
}
