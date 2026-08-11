import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Fuseau d'une activité")
struct ActivityTimeZoneTests {
    @Test("l'identifiant est lu derrière le décalage de Strava")
    func theIdentifierIsReadAfterTheOffset() {
        #expect(
            ActivityTimeZone.parse("(GMT+01:00) Europe/Paris")?.identifier
                == "Europe/Paris"
        )
        #expect(
            ActivityTimeZone.parse("(GMT+11:00) Pacific/Noumea")?.identifier
                == "Pacific/Noumea"
        )
    }

    @Test("un identifiant seul passe aussi")
    func abareIdentifierWorksToo() {
        #expect(ActivityTimeZone.parse("Europe/Paris")?.identifier == "Europe/Paris")
    }

    @Test("rien, ou n'importe quoi, ne donne pas de fuseau")
    func nothingUsableGivesNothing() {
        #expect(ActivityTimeZone.parse(nil) == nil)
        #expect(ActivityTimeZone.parse("") == nil)
        #expect(ActivityTimeZone.parse("(GMT+01:00) Pas/Un/Fuseau") == nil)
    }

    @Test("le décalage imprimé par Strava est ignoré, et c'est le sujet")
    func theprintedOffsetIsIgnored() {
        // Strava prints the zone's *standard* offset, which does not move with
        // daylight saving: a Paris outing carries « (GMT+01:00) » in August as
        // in January. Trusting it would put every summer outing an hour early.
        // Only the identifier knows that 11 August 2026 is +02:00 in Paris.
        let zone = ActivityTimeZone.parse("(GMT+01:00) Europe/Paris")!
        let august = Date(timeIntervalSince1970: 1_786_423_931)  // 2026-08-11
        #expect(zone.secondsFromGMT(for: august) == 7_200)
    }
}

@Suite("Heures d'activité, dans leur fuseau")
struct ActivityDateFormattingTests {
    /// 2026-08-11 04:52:11 UTC — 06:52 in Paris, where the outing happened.
    private let instant = Date(timeIntervalSince1970: 1_786_423_931)
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let noumea = TimeZone(identifier: "Pacific/Noumea")!

    @Test("l'heure est celle de la pendule du lieu, pas celle du lecteur")
    func theClockIsTheOneWhereItHappened() {
        #expect(Format.time(instant, in: paris) == "06:52")
        // The same instant, read from where it is already the afternoon.
        #expect(Format.time(instant, in: noumea) == "15:52")
    }

    @Test("la date complète porte l'heure du lieu")
    func theLongDateCarriesThatClock() {
        #expect(Format.longDate(instant, in: paris) == "mardi 11 août 2026 à 06:52")
    }

    @Test("la date courte et la date numérique suivent le même fuseau")
    func theShortFormsFollowTheSameZone() {
        #expect(Format.dateOnly(instant, in: paris) == "11 août 2026")
        #expect(Format.numericDate(instant, in: paris) == "11/08/2026")
    }

    @Test("un fuseau peut changer le jour, pas seulement l'heure")
    func azoneCanMoveTheDay() {
        // 2026-08-11 22:30 UTC is already the 12th in Nouméa (+11).
        let lateEvening = Date(timeIntervalSince1970: 1_786_487_400)
        #expect(Format.numericDate(lateEvening, in: paris) == "12/08/2026")
        #expect(Format.numericDate(lateEvening, in: noumea) == "12/08/2026")
        let earlier = Date(timeIntervalSince1970: 1_786_464_000)  // 16:00 UTC
        #expect(Format.numericDate(earlier, in: paris) == "11/08/2026")
        #expect(Format.numericDate(earlier, in: noumea) == "12/08/2026")
    }

    @Test("le nom de fichier GPX est trié et lisible partout pareil")
    func thefileDateIsSortableAndStable() {
        #expect(Format.fileDate(instant, in: paris) == "2026-08-11")
        #expect(Format.fileDate(instant, in: noumea) == "2026-08-11")
    }
}

@Suite("Éditer une activité ne la déplace pas dans le temps")
@MainActor
struct ActivityDraftTimeZoneTests {
    /// 2026-08-11 04:52:11 UTC — 06:52 in Paris, where it happened.
    private let instant = Date(timeIntervalSince1970: 1_786_423_931)

    private func parisActivity(in context: ModelContext) throws -> Activity {
        let activity = Activity(stravaID: 1, name: "Fractionné", sportType: .run)
        activity.startDate = instant
        // The wall clock, stored as Strava sends it: the hour that was on the
        // clock, encoded as if it were UTC.
        activity.startLocalDate = instant.addingTimeInterval(7_200)
        activity.timezoneIdentifier = "(GMT+01:00) Europe/Paris"
        context.insert(activity)
        try context.save()
        return activity
    }

    @Test("le brouillon porte l'instant, et le fuseau où le lire")
    func thedraftCarriesTheInstantAndItsZone() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try parisActivity(in: context)
        let draft = ActivityDraft(activity)
        #expect(draft.startDate == instant)
        #expect(draft.timeZone.identifier == "Europe/Paris")
        // Which is what the picker shows: 06:52, not 08:52.
        #expect(Format.time(draft.startDate, in: draft.timeZone) == "06:52")
    }

    @Test("enregistrer sans toucher à la date ne bouge rien")
    func savingAnUntouchedDateMovesNothing() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try parisActivity(in: context)
        let before = (activity.startDate, activity.startLocalDate)
        var draft = ActivityDraft(activity)
        draft.name = "Autre nom"
        draft.apply(to: activity)
        #expect(activity.startDate == before.0)
        #expect(activity.startLocalDate == before.1)
        // This is the regression that mattered: the sheet used to hand the
        // wall-clock stamp back as an instant, and every save pushed the
        // outing two hours later.
        #expect(activity.startDate == instant)
    }

    @Test("déplacer la date déplace les deux dates du même écart")
    func movingTheDateMovesBothByTheSameAmount() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try parisActivity(in: context)
        var draft = ActivityDraft(activity)
        draft.startDate = instant.addingTimeInterval(3_600)
        draft.apply(to: activity)
        #expect(activity.startDate == instant.addingTimeInterval(3_600))
        // The offset between the two is what makes the stored wall clock mean
        // anything; a save must never quietly close it.
        #expect(
            activity.startLocalDate.timeIntervalSince(activity.startDate) == 7_200
        )
        #expect(Format.time(activity.startDate, in: activity.timeZone) == "07:52")
    }

    @Test("une activité saisie à la main reçoit le fuseau du Mac")
    func ahandEnteredActivityGetsThisMacsZone() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let draft = ActivityDraft(startingOn: instant)
        let activity = draft.makeActivity()
        context.insert(activity)
        #expect(activity.timezoneIdentifier == TimeZone.current.identifier)
    }

    @Test("un fuseau déjà connu n'est jamais réécrit par la fenêtre d'édition")
    func aknownZoneIsNeverOverwritten() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try parisActivity(in: context)
        var draft = ActivityDraft(activity)
        draft.name = "Autre nom"
        draft.apply(to: activity)
        #expect(activity.timezoneIdentifier == "(GMT+01:00) Europe/Paris")
    }
}

@Suite("Les statistiques rangent la sortie dans son propre jour")
@MainActor
struct ActivityStatisticsTimeZoneTests {
    /// 2026-08-31 21:30 UTC — 23:30 in Paris, still the 31st of August there,
    /// and the last day of the month. Read on a clock that adds the offset a
    /// second time, it became 01:30 on 1 September: the wrong day, the wrong
    /// week, and the wrong bar of the histogram.
    private let lateAugustEvening = Date(timeIntervalSince1970: 1_788_211_800)

    private func parisRun(in context: ModelContext) throws -> Activity {
        let activity = Activity(stravaID: 1, name: "Sortie du soir", sportType: .run)
        activity.startDate = lateAugustEvening
        activity.startLocalDate = lateAugustEvening.addingTimeInterval(7_200)
        activity.timezoneIdentifier = "(GMT+01:00) Europe/Paris"
        activity.distance = 10_000
        context.insert(activity)
        try context.save()
        return activity
    }

    @Test("une sortie de 23 h 30 reste au dernier jour d'août")
    func alateEveningRunStaysInAugust() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try parisRun(in: context)
        let day = try #require(ActivityStatistics.day(of: activity))
        // Read back in the reader's calendar, which is the one `day(of:)`
        // rebuilds in — so this holds whatever zone the machine is set to.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 31)
    }

    @Test("le jour est celui de la pendule du lieu, même vu d'ailleurs")
    func thedayIsTheOneWhereItHappened() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try parisRun(in: context)
        // The same instant is already 08:30 on 1 September in Nouméa. Filed
        // there, the run belongs to 1 September — the day it was run *on that
        // clock*, which is the whole point of reading the zone rather than
        // assuming the reader's.
        activity.timezoneIdentifier = "(GMT+11:00) Pacific/Noumea"
        let elsewhere = try #require(ActivityStatistics.day(of: activity))
        let parts = Calendar.current.dateComponents(
            [.month, .day], from: elsewhere
        )
        #expect(parts.month == 9)
        #expect(parts.day == 1)
    }

    @Test("midi, pour se tenir loin des deux bords d'un changement d'heure")
    func noonKeepsItAwayFromTheDaylightSavingEdges() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = try parisRun(in: context)
        let day = try #require(ActivityStatistics.day(of: activity))
        #expect(Calendar.current.component(.hour, from: day) == 12)
    }
}
