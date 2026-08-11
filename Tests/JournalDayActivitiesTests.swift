import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Activités du jour, au-dessus de la note")
@MainActor
struct JournalDayActivitiesTests {
    // MARK: - Les chiffres rappelés

    @Test("distance, durée et dénivelé, séparés par des points médians")
    func allThreeFigures() {
        #expect(
            JournalDayActivities.figures(
                distance: 12_400, movingTime: 3_720, elevation: 350
            ) == "12,4 km · 1 h 02 · 350 m"
        )
    }

    @Test("un chiffre absent est omis plutôt que tiré")
    func absentFiguresAreLeftOut() {
        // A swim has no climb worth printing; a row of dashes says nothing an
        // absent figure does not say better.
        #expect(
            JournalDayActivities.figures(
                distance: 1_500, movingTime: 2_400, elevation: 0
            ) == "1,5 km · 40 min"
        )
        // A gym session has no distance at all.
        #expect(
            JournalDayActivities.figures(
                distance: 0, movingTime: 3_600, elevation: 0
            ) == "1 h 00"
        )
    }

    @Test("une activité sans aucun chiffre ne rend rien")
    func nothingToShowRendersEmpty() {
        #expect(
            JournalDayActivities.figures(
                distance: 0, movingTime: 0, elevation: 0
            ).isEmpty
        )
    }

    // MARK: - Les bornes du jour

    @Test("le jour va de minuit local à minuit local")
    func theDaySpansLocalMidnights() {
        let (start, end) = JournalDayActivities.dayRange(DateKey(raw: "2026-08-11")!)
        #expect(DateKey(start) == DateKey(raw: "2026-08-11")!)
        #expect(DateKey(end) == DateKey(raw: "2026-08-12")!)
        var calendar = Calendar.current
        calendar.timeZone = .current
        #expect(calendar.component(.hour, from: start) == 0)
        #expect(calendar.component(.minute, from: start) == 0)
    }

    @Test("une sortie de 23 h 40 reste au jour où elle a commencé")
    func alateEveningOutingStaysOnItsDay() {
        let day = DateKey(raw: "2026-08-11")!
        let (start, end) = JournalDayActivities.dayRange(day)
        let evening = Calendar.current.date(
            bySettingHour: 23, minute: 40, second: 0, of: day.date()
        )!
        #expect(evening >= start && evening < end)
    }

    @Test("une sortie de 00 h 10 appartient au lendemain")
    func anEarlyMorningOutingBelongsToTheNextDay() {
        let (_, end) = JournalDayActivities.dayRange(DateKey(raw: "2026-08-11")!)
        let earlyNextDay = Calendar.current.date(
            bySettingHour: 0, minute: 10, second: 0,
            of: DateKey(raw: "2026-08-12")!.date()
        )!
        #expect(earlyNextDay >= end)
    }

    @Test("un changement d'heure ne décale pas les bornes")
    func daylightSavingDoesNotShiftTheBounds() {
        // In Paris, 25 October 2026 is 25 hours long and 29 March 2026 is 23.
        // Adding 86 400 seconds would land inside the day in one case and an
        // hour into the next in the other; going through `DateKey` cannot.
        for raw in ["2026-10-25", "2026-03-29"] {
            let day = DateKey(raw: raw)!
            let (start, end) = JournalDayActivities.dayRange(day)
            #expect(DateKey(start) == day)
            #expect(DateKey(end) == day.advanced(by: 1))
            #expect(Calendar.current.component(.hour, from: end) == 0)
        }
    }
}

@Suite("La note de l'activité rappelée")
@MainActor
struct JournalDayActivityNoteTests {
    private func activity(note: String?) throws -> Activity {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        activity.activityDescription = note
        context.insert(activity)
        try context.save()
        return activity
    }

    @Test("la note est rendue telle qu'elle a été écrite")
    func theNoteComesThrough() throws {
        #expect(
            JournalDayActivities.note(of: try activity(note: "Jambes lourdes."))
                == "Jambes lourdes."
        )
    }

    @Test("une activité sans note n'en montre pas")
    func noNoteAtAll() throws {
        #expect(JournalDayActivities.note(of: try activity(note: nil)).isEmpty)
    }

    @Test("une note faite de blancs compte pour vide")
    func whitespaceOnlyCountsAsEmpty() throws {
        // An editor that left a stray newline behind must not open a card on a
        // blank line.
        #expect(JournalDayActivities.note(of: try activity(note: "  \n\n ")).isEmpty)
    }

    @Test("les blancs autour d'une vraie note sont retirés")
    func surroundingWhitespaceIsTrimmed() throws {
        #expect(
            JournalDayActivities.note(of: try activity(note: "\n  Vent de face.  \n"))
                == "Vent de face."
        )
    }
}
