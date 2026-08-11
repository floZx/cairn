import Testing
import Foundation
@testable import Cairn

@Suite("Un jour du journal, les deux sources réunies")
struct JournalDayTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func note(_ raw: String, _ text: String) -> JournalNote {
        JournalNote(date: key(raw), text: text)
    }

    // MARK: - La fusion

    @Test("un jour du coffre garde sa note et gagne celles de ses sorties")
    func avaultDayGainsItsOutings() {
        let days = JournalDay.merge(
            notes: [note("2026-08-11", "Journée calme.")],
            activityNotes: [key("2026-08-11"): ["Jambes lourdes."]]
        )
        #expect(days.count == 1)
        #expect(days[0].note.text == "Journée calme.")
        #expect(days[0].activityNotes == ["Jambes lourdes."])
    }

    @Test("un jour sans fichier existe si une sortie a écrit quelque chose")
    func anOutingAloneMakesADay() {
        let days = JournalDay.merge(
            notes: [], activityNotes: [key("2026-08-09"): ["Vent de face."]]
        )
        #expect(days.map(\.date.raw) == ["2026-08-09"])
        #expect(days[0].note.text.isEmpty)
        #expect(days[0].summary == "Vent de face.")
    }

    @Test("un jour dont les sorties n'ont rien dit n'entre pas")
    func asilentDayStaysOut() {
        // A day trained on without a word is not a journal entry.
        #expect(
            JournalDay.merge(
                notes: [], activityNotes: [key("2026-08-09"): ["", "  \n "]]
            ).isEmpty
        )
    }

    @Test("la ligne du jour qu'on écrit survit, même vide")
    func theOpenDayKeepsItsRow() {
        // The store holds an empty note for the day being written — ⌘N on a day
        // with nothing yet. Dropping it here would take the pane away, and the
        // caret with it, in the middle of a sentence.
        let days = JournalDay.merge(
            notes: [note("2026-08-11", "")], activityNotes: [:]
        )
        #expect(days.map(\.date.raw) == ["2026-08-11"])
    }

    @Test("les jours sortent de la plus récente à la plus ancienne")
    func daysComeOutNewestFirst() {
        let days = JournalDay.merge(
            notes: [note("2026-08-09", "a"), note("2026-08-11", "b")],
            activityNotes: [key("2026-08-10"): ["c"]]
        )
        #expect(days.map(\.date.raw) == ["2026-08-11", "2026-08-10", "2026-08-09"])
    }

    // MARK: - Ce que le jour dit

    @Test("le résumé préfère la note du jour à celle d'une sortie")
    func thedaysOwnNoteComesFirst() {
        // One is written *about the day*, the other about an outing in it.
        let day = JournalDay(
            date: key("2026-08-11"),
            note: note("2026-08-11", "Journée calme."),
            activityNotes: ["Jambes lourdes."]
        )
        #expect(day.summary == "Journée calme.")
    }

    @Test("les tags des deux sources sont comptés ensemble")
    func tagsComeFromBothSources() {
        let day = JournalDay(
            date: key("2026-08-11"),
            note: note("2026-08-11", "Promenade avec #Sam."),
            activityNotes: ["Sortie #vélo, #projet/cairn en tête."]
        )
        #expect(
            day.tags == Set([
                JournalTag(name: "Sam")!,
                JournalTag(name: "vélo")!,
                JournalTag(name: "projet")!,
                JournalTag(name: "projet/cairn")!,
            ])
        )
    }

    // MARK: - La recherche

    @Test("la recherche trouve dans la note du jour comme dans celle d'une sortie")
    func searchReadsBothSources() {
        let day = JournalDay(
            date: key("2026-08-11"),
            note: note("2026-08-11", "Journée calme."),
            activityNotes: ["Jambes lourdes, vent de face."]
        )
        #expect(day.matches(query: "calme"))
        #expect(day.matches(query: "jambes lourdes"))
        #expect(!day.matches(query: "natation"))
    }

    @Test("un jour né d'une sortie répond aux recherches")
    func anOutingOnlyDayIsSearchable() {
        let day = JournalDay(
            date: key("2026-08-09"), activityNotes: ["Vent de face."]
        )
        #expect(day.matches(query: "VENT"))
        #expect(day.excerpt(matching: "vent") == "Vent de face.")
    }

    @Test("l'extrait vient du texte qui a répondu")
    func theExcerptComesFromWhicheverMatched() {
        let day = JournalDay(
            date: key("2026-08-11"),
            note: note("2026-08-11", "Journée calme."),
            activityNotes: ["Jambes lourdes."]
        )
        #expect(day.excerpt(matching: "calme") == "Journée calme.")
        #expect(day.excerpt(matching: "lourdes") == "Jambes lourdes.")
    }

    @Test("le filtre cumule recherche et tags sur les deux sources")
    func filterCombinesBoth() {
        let days = JournalDay.merge(
            notes: [note("2026-08-11", "Journée calme.")],
            activityNotes: [
                key("2026-08-11"): ["Jambes lourdes avec #Sam."],
                key("2026-08-09"): ["Vent de face."],
            ]
        )
        #expect(JournalDay.filter(days, query: "", tags: []).count == 2)
        #expect(
            JournalDay.filter(days, query: "vent", tags: []).map(\.date.raw)
                == ["2026-08-09"]
        )
        // The tag lives in an outing's note, and ticking it must still find the
        // day — which is the whole point of counting both.
        #expect(
            JournalDay.filter(
                days, query: "", tags: [JournalTag(name: "Sam")!]
            ).map(\.date.raw) == ["2026-08-11"]
        )
    }
}
