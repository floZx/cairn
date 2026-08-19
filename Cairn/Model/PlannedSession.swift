import Foundation
import SwiftData

/// Une séance prévue, un jour donné.
///
/// Le plan d'entraînement vivait dans un calendrier macOS, hors de portée du
/// téléphone : un événement d'EventKit ne traverse pas, la version web n'y a
/// aucun accès. Le porter ici lui donne les deux écrans, le miroir, et le
/// rapprochement avec ce qui a réellement été fait.
///
/// Un modèle par séance et non par jour : une journée à double séance — footing
/// le matin, natation le midi — est le cas courant d'un plan, et un modèle par
/// jour l'aurait forcée dans un champ unique.
@Model
final class PlannedSession {
    #Index<PlannedSession>([\.dateKeyRaw])

    /// Identité locale stable, indépendante de tout service : c'est elle qui
    /// rend la ligne reconnaissable d'un magasin à l'autre.
    var uuid: String = UUID().uuidString

    var dateKeyRaw: String = ""

    /// Le sport prévu, dans le vocabulaire de `SportType` — celui des sorties.
    ///
    /// La même chaîne que `Activity.sportTypeRaw`, et c'est délibéré : c'est
    /// elle qui donne l'icône, la couleur, et surtout le rapprochement avec la
    /// sortie qui accomplira la séance.
    var sportTypeRaw: String = SportType.other.rawValue

    /// « 6×45″ en côte », « Sortie longue », « Récupération ».
    var title: String = ""

    /// Ce qu'on vise, quand on vise quelque chose.
    ///
    /// Facultatifs tous les trois, et pour la raison qui vaut déjà pour les
    /// fibres : une séance sans objectif chiffré n'en a pas zéro, elle n'en a
    /// pas. Un footing « une heure tranquille » n'a pas de distance, et un zéro
    /// affiché mentirait sur l'intention.
    var plannedDistance: Double?
    var plannedDuration: Double?
    var plannedElevation: Double?

    /// Le détail, en markdown comme les notes de sortie : séries, allures,
    /// consignes.
    var notes: String = ""

    /// Le type de journée nutrition que cette séance appelle.
    ///
    /// Planifier une sortie longue et l'objectif calorique qui va avec est le
    /// même geste ; les séparer obligeait à le refaire deux fois.
    var dayType: DayType?

    /// L'ordre dans la journée, pour lire une double séance dans l'ordre où
    /// elle se vit.
    var sortOrder: Int = 0

    init(
        dateKey: DateKey,
        sportTypeRaw: String,
        title: String,
        plannedDistance: Double? = nil,
        plannedDuration: Double? = nil,
        plannedElevation: Double? = nil,
        notes: String = "",
        dayType: DayType? = nil,
        sortOrder: Int = 0
    ) {
        self.dateKeyRaw = dateKey.raw
        self.sportTypeRaw = sportTypeRaw
        self.title = title
        self.plannedDistance = plannedDistance
        self.plannedDuration = plannedDuration
        self.plannedElevation = plannedElevation
        self.notes = notes
        self.dayType = dayType
        self.sortOrder = sortOrder
    }

    var dateKey: DateKey? { DateKey(raw: dateKeyRaw) }

    /// Lu comme `Activity.sport` le fait, `.other` couvrant l'inconnu.
    var sport: SportType { SportType(rawValue: sportTypeRaw) ?? .other }
}
