import Testing
import Foundation
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
