import Foundation
import SwiftData

/// A day of the journal, whatever was written about it and wherever.
///
/// The list used to be the folder's files and nothing else, so a day one had
/// written about only on the outing itself — "jambes lourdes, vent de face" in
/// a Strava note — was in the journal but nowhere in the journal's list, and no
/// search would find it. This is the vault and everywhere else read as one
/// memory: the day's own note from the vault, and whatever was written about
/// it elsewhere in the app the same day — an outing's note, a meal's, a
/// weigh-in's comment.
///
/// The vault stays the only thing Cairn *writes*. Those other texts are read
/// here and edited where they live, each in the place that wrote it.
struct JournalDay: Identifiable, Equatable, Sendable {
    let date: DateKey
    /// The vault's file for this day. Its text is empty when there is none —
    /// which is exactly the note that starts existing when one types into it.
    let note: JournalFileNote
    /// What was written about this day anywhere but the vault: an outing's own
    /// note, a meal's, a weigh-in's. One list and not three, because nothing
    /// downstream asks where a sentence came from — the row's summary, the
    /// search and the tags all want the text and nothing else. The pane, which
    /// does need to tell them apart, does not read this: it queries the store
    /// for the day itself.
    ///
    /// In the order a day is lived: the outings first, then the meals, the
    /// weigh-in last. That order is what picks the line standing for a day
    /// with no file of its own.
    let elsewhereNotes: [String]
    /// What the day *did*, as opposed to what was written about it: the sports
    /// it holds and whether it was weighed. Shown as marks in the list, where
    /// a coloured glyph says at a glance what a sentence would have to spell
    /// out — and where an outing that wrote nothing still counts, which is the
    /// difference between these and `elsewhereNotes`.
    let marks: Marks
    /// Les étiquettes des textes écrits ailleurs que dans le carnet.
    ///
    /// Tenues plutôt que relues : `tags` les tirait des textes à **chaque
    /// lecture**, et la barre latérale les relit une fois par journée à chaque
    /// rendu pour compter ses tags. Mesuré le 31 août 2026 : 19 ms par appel,
    /// pour des textes qui n'avaient pas bougé — un jour raconté est raconté
    /// une fois pour toutes, seule la note du carnet suit la frappe.
    ///
    /// `JournalLibraryCache` les calcule avec le reste de la bibliothèque. Un
    /// appelant qui n'en fournit pas les fait calculer par `init` depuis les
    /// textes : le raccourci ne peut pas se prendre par mégarde, et une
    /// journée n'a jamais moins d'étiquettes que ce qu'elle dit.
    let elsewhereTags: Set<JournalTag>

    /// The day's silent facts, gathered by `JournalDaySources`.
    struct Marks: Equatable, Sendable {
        /// One entry per distinct sport, in the order they happened: three
        /// runs in a day are one running glyph, not three.
        var sports: [SportType] = []
        var weighed = false
        /// The day's outings' photos, in the order they were taken. Held as
        /// identifiers and not as objects: this value is compared to diff the
        /// list, and a model object is neither `Sendable` nor cheap to hold.
        var photoIDs: [PersistentIdentifier] = []

        static let none = Marks()
    }

    var id: DateKey { date }

    init(
        date: DateKey, note: JournalFileNote? = nil, elsewhereNotes: [String] = [],
        marks: Marks = .none, elsewhereTags: Set<JournalTag>? = nil
    ) {
        self.date = date
        self.note = note ?? JournalFileNote(date: date, text: "")
        self.elsewhereNotes = elsewhereNotes
        self.marks = marks
        self.elsewhereTags = elsewhereTags
            ?? elsewhereNotes.reduce(into: []) { $0.formUnion(JournalTagScanner.tags(in: $1)) }
    }

    /// The tags of every source together.
    ///
    /// An elsewhere note is a database field rather than a file in the vault,
    /// but the person writing `#Sam` in one meant the same thing as in the
    /// other, and a tag list that answered only for half of them would be a
    /// tag list one cannot trust.
    var tags: Set<JournalTag> {
        note.tags.union(elsewhereTags)
    }

    /// The line that stands for the day when nothing is being searched for.
    ///
    /// The day's own note first: it is the one written *about* the day, where
    /// an elsewhere note is written about the outing, the meal or the
    /// weigh-in it belongs to. A day that exists only because of one of those
    /// falls back to what it said.
    var summary: String {
        note.isEmpty
            ? (elsewhereNotes.first.map { JournalFileNote(date: date, text: $0).summary } ?? "")
            : note.summary
    }

    func matches(query: String) -> Bool {
        note.matches(query: query)
            || elsewhereNotes.contains { JournalFileNote.matches($0, query: query) }
    }

    /// The passage that answered the search, from whichever text answered it.
    func excerpt(matching query: String) -> String? {
        note.excerpt(matching: query)
            ?? elsewhereNotes.lazy
                .compactMap { JournalFileNote.excerpt(of: $0, matching: query) }
                .first
    }

    func has(_ required: Set<JournalTag>) -> Bool {
        required.isSubset(of: tags)
    }

    /// The vault and everywhere else merged, newest first.
    ///
    /// `notes` wins on identity: a day with a file keeps that file's note and
    /// gains what was written elsewhere about it beside it. **Every note the
    /// store lists is kept, empty or not** — the store holds an empty row on
    /// purpose for the day being written, and dropping it here would take
    /// the pane, and the caret in it, away mid-sentence.
    ///
    /// A day that exists only because something was written elsewhere is
    /// added only when that text says something: a day trained on, eaten
    /// through and weighed in silence is not a journal entry.
    static func merge(
        notes: [JournalFileNote], elsewhereNotes: [DateKey: [String]],
        marks: [DateKey: Marks] = [:], elsewhereTags: [DateKey: Set<JournalTag>]? = nil
    ) -> [JournalDay] {
        // `elsewhereTags.map` et non `elsewhereTags?[…]` : fourni, un jour
        // absent du dictionnaire n'a pas d'étiquette, et c'est une réponse ;
        // absent, chaque journée relit ses textes, et c'est le repli.
        var days: [JournalDay] = notes.map { note in
            JournalDay(
                date: note.date, note: note,
                elsewhereNotes: spoken(elsewhereNotes[note.date]),
                marks: marks[note.date] ?? .none,
                elsewhereTags: elsewhereTags.map { $0[note.date] ?? [] }
            )
        }
        let written = Set(notes.map(\.date))
        for (date, texts) in elsewhereNotes where !written.contains(date) {
            let said = spoken(texts)
            guard !said.isEmpty else { continue }
            days.append(
                JournalDay(
                    date: date, elsewhereNotes: said, marks: marks[date] ?? .none,
                    elsewhereTags: elsewhereTags.map { $0[date] ?? [] }
                )
            )
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
        // Deux sorties sèches avant de travailler. Sans tag coché, `has`
        // relisait les étiquettes de chaque texte de chaque journée pour
        // vérifier qu'un ensemble vide y est inclus — ce qui est vrai
        // d'avance. Mesuré le 31 août 2026 : 97 ms par tranche de deux
        // secondes dans le journal, pour une question dont la réponse était
        // connue avant d'être posée.
        guard !query.isEmpty || !tags.isEmpty else { return days }
        return days.filter {
            (tags.isEmpty || $0.has(tags)) && (query.isEmpty || $0.matches(query: query))
        }
    }
}
