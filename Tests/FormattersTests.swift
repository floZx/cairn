import Testing
import Foundation
@testable import Cairn

@Suite("Format")
struct FormattersTests {
    @Test("les distances sous 1 km sont en mètres, au-dessus en kilomètres")
    func formatsDistance() {
        #expect(Format.distance(0) == "0 m")
        #expect(Format.distance(850) == "850 m")
        #expect(Format.distance(45_231.4).contains("45,2"))
        #expect(Format.distance(45_231.4).hasSuffix("km"))
    }

    @Test("les durées passent en h/min/s selon leur longueur")
    func formatsDuration() {
        #expect(Format.duration(0) == "0 s")
        #expect(Format.duration(45) == "45 s")
        #expect(Format.duration(90) == "1 min 30 s")
        #expect(Format.duration(3600) == "1 h 00")
        #expect(Format.duration(5412) == "1 h 30")
    }

    @Test("la durée compacte s'arrête à la minute, arrondie")
    func formatsCompactDuration() {
        #expect(Format.durationCompact(90) == "2 min")
        #expect(Format.durationCompact(5385) == "1 h 30")
        // A carry across the hour must not produce "0 h 60".
        #expect(Format.durationCompact(3599) == "1 h 00")
        // Never zero minutes, which would read as an activity of no length.
        #expect(Format.durationCompact(0) == "< 1 min")
        #expect(Format.durationCompact(20) == "< 1 min")
    }

    @Test("la fréquence cardiaque absente donne un tiret")
    func formatsHeartRate() {
        #expect(Format.heartrate(142.6) == "143 bpm")
        #expect(Format.heartrate(nil) == "—")
        // Strava sends 0 for some manual entries; that is "no monitor" too.
        #expect(Format.heartrate(0) == "—")
    }

    @Test("le dénivelé est arrondi au mètre")
    func formatsElevation() {
        #expect(Format.elevation(612.4) == "612 m")
    }

    @Test("la vitesse devient une allure pour les sports de course")
    func formatsSpeedBySport() {
        // 2,78 m/s ≈ 10 km/h → 6:00/km
        #expect(Format.speed(2.7778, sport: .run).contains("/km"))
        #expect(Format.speed(2.7778, sport: .ride).contains("km/h"))
    }

    @Test("une vitesse nulle ne produit pas d'allure absurde")
    func handlesZeroSpeed() {
        #expect(Format.speed(0, sport: .run) == "—")
        #expect(Format.speed(0, sport: .ride) == "—")
    }

    @Test("les mesures absentes affichent un tiret")
    func formatsMissingValues() {
        #expect(Format.heartrate(nil) == "—")
        #expect(Format.power(nil) == "—")
        #expect(Format.heartrate(138.4) == "138 bpm")
        #expect(Format.power(156.3) == "156 W")
    }

    @Test("le dénivelé au kilomètre s'arrondit et gère l'absence de distance")
    func formatsElevationPerKilometre() {
        #expect(Format.elevationPerKilometre(23.4) == "23 m/km")
        #expect(Format.elevationPerKilometre(0) == "—")
    }

    @Test("la date de la liste n'affiche pas l'heure")
    func listDateOmitsTime() {
        // 2026-08-05T12:33:00Z, soit 14:33 en heure de Paris.
        let date = Date(timeIntervalSince1970: 1_785_933_180)
        let formatted = Format.dateOnly(date)
        #expect(formatted.contains("août"))
        #expect(!formatted.contains("14:33"))
        #expect(!formatted.contains(":"))
    }

    @Test("la natation s'exprime en allure aux 100 m, pas au kilomètre")
    func formatsSwimPacePerHundredMetres() {
        // 1000 m en 25 min = 0,6667 m/s → 2:30 aux 100 m.
        #expect(Format.speed(0.6667, sport: .swim) == "2:30/100 m")
        #expect(Format.speed(0, sport: .swim) == "—")
    }

    @Test("les dates sont en français quelle que soit la langue du système")
    func formatsDatesInFrench() {
        // 2026-08-05T12:33:00Z, soit le 5 août 2026 à 14:33 en heure de Paris.
        let date = Date(timeIntervalSince1970: 1_785_933_180)
        #expect(Format.longDate(date).contains("août"))
        #expect(Format.shortDate(date).contains("août"))
        #expect(!Format.longDate(date).contains("August"))
    }
}
