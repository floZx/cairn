import Foundation
import SwiftData

/// L'écart entre les zones de FC de Strava et celles de la sortie Garmin la
/// plus récente.
///
/// Garmin fait bouger ses zones seul, quand la montre revoit la FC max ou le
/// seuil ; Strava garde celles qu'on y a saisies, et son API ne permet pas de
/// les écrire. Cairn ne peut donc que prévenir. Seuls les planchers des zones
/// 2 à 5 se comparent : la zone 1 part de 0 chez Strava, d'environ la moitié
/// de la FC max chez Garmin.
struct HeartRateZoneDrift: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let zone: Int
        let garmin: Int
        let strava: Int
        var differs: Bool { garmin != strava }
    }

    /// Le jour de la sortie Garmin qui sert de référence.
    let activityDate: Date
    /// Les zones 2 à 5, qu'elles diffèrent ou non.
    let rows: [Row]

    /// Les planchers des zones Strava, zone 1 d'abord. L'API brute écrit les
    /// zones bout à bout, le `min` d'une zone reprenant le `max` de la
    /// précédente : `{"min": 130, "max": 143}` pour une zone 2 que Strava
    /// affiche « 131 – 143 ». Le plancher est donc le `max` d'avant plus un —
    /// lire le `min` décalait tout d'un battement, et l'alerte revenait avec
    /// des zones pourtant à jour (signalé le 29 septembre 2026).
    static func stravaFloors(_ zones: [AthleteZonesDTO.Range]) -> [Int] {
        guard let first = zones.first else { return [] }
        return [first.min] + zones.dropLast().map { $0.max + 1 }
    }

    /// Nil quand les zones concordent, ou quand l'une des deux listes n'a pas
    /// ses cinq zones — rien de sûr à comparer.
    static func compare(
        garminFloors: [Double], stravaFloors: [Int], activityDate: Date
    ) -> HeartRateZoneDrift? {
        guard garminFloors.count == 5, stravaFloors.count == 5 else { return nil }
        let rows = (1..<5).map {
            Row(zone: $0 + 1, garmin: Int(garminFloors[$0].rounded()), strava: stravaFloors[$0])
        }
        guard rows.contains(where: \.differs) else { return nil }
        return HeartRateZoneDrift(activityDate: activityDate, rows: rows)
    }

    /// La sortie la plus récente dont Garmin a donné les zones de FC.
    @MainActor
    static func latestGarminZones(in context: ModelContext) -> (date: Date, floors: [Double])? {
        let debut = GarminZonesFetcher.firstWatchDay
        var descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.startDate >= debut && $0.zonesCheckedAt != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        guard let recentes = try? context.fetch(descriptor),
              let activity = recentes.first(where: { $0.hrZoneFloors != nil }),
              let floors = activity.hrZoneFloors
        else { return nil }
        return (activity.startDate, floors)
    }

    /// Le texte de l'alerte : chaque zone, la valeur Garmin d'abord, celle de
    /// Strava entre parenthèses quand elle diffère.
    var message: String {
        let lignes = rows.map { row in
            row.differs
                ? "Z\(row.zone) : \(row.garmin) bpm (Strava : \(row.strava))"
                : "Z\(row.zone) : \(row.garmin) bpm"
        }
        return """
            D'après la sortie Garmin du \(Format.fullDate(activityDate)), les zones \
            de fréquence cardiaque ont changé ; Strava a gardé les anciennes.

            \(lignes.joined(separator: "\n"))
            """
    }

    /// La page de Strava où se règlent les zones — l'API ne les écrit pas.
    static let stravaSettingsURL = URL(string: "https://www.strava.com/settings/performance")!
}
