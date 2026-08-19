import Foundation
import SwiftData

/// Le pont entre une séance prévue et le budget calorique du jour.
///
/// Le type de journée porté par une séance ne servait jusqu'ici qu'à
/// s'afficher dans la case du calendrier — signalé, et c'était juste. Il est
/// pourtant là pour une raison précise : planifier une sortie longue et
/// l'objectif calorique qui va avec est le même geste, et les séparer oblige
/// à le refaire deux fois.
enum TrainingNutrition {
    /// Pose le type de journée de la séance sur la journée nutrition
    /// correspondante. Rend vrai si quelque chose a changé.
    ///
    /// **N'écrase jamais un type déjà choisi.** Une journée dont on a réglé le
    /// budget à la main l'a été pour une raison que le plan ne connaît pas —
    /// un repas de famille, une journée de repos décidée le matin — et la
    /// replanification d'une séance ne doit pas la reprendre. Le plan propose
    /// tant que rien n'a été dit ; dès que quelque chose l'a été, il se tait.
    @discardableResult
    static func appliquer(
        _ seance: PlannedSession, dans context: ModelContext
    ) throws -> Bool {
        guard let type = seance.dayType else { return false }
        // La chaîne sortie de la fermeture : un `#Predicate` ne sait pas
        // traverser une propriété d'une valeur capturée.
        let jour = seance.dateKeyRaw
        let existantes = try context.fetch(
            FetchDescriptor<NutritionDay>(
                predicate: #Predicate { $0.dateKeyRaw == jour }
            )
        )

        if let journee = existantes.first {
            guard journee.dayType == nil else { return false }
            journee.dayType = type
            return true
        }

        // Aucune journée en base : la plupart des jours à venir sont dans ce
        // cas, et c'est bien le moment de la créer — c'est elle qui portera le
        // budget quand on ouvrira l'écran des repas.
        guard let dateKey = seance.dateKey else { return false }
        context.insert(NutritionDay(dateKey: dateKey, dayType: type))
        return true
    }
}
