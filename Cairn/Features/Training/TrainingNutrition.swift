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

extension TrainingNutrition {
    /// Ce que la déduction poserait, jour par jour — sans rien écrire.
    ///
    /// Un aperçu avant d'agir, comme pour l'import du calendrier, et pour la
    /// même raison : la règle est une devinette. Mieux vaut lire trente lignes
    /// que découvrir trois cents budgets posés de travers.
    struct Proposition: Identifiable {
        var dateKey: DateKey
        var type: DayType
        /// Ce que le plan dit ce jour-là, en une ligne.
        var resume: String

        var id: String { dateKey.raw }
    }

    /// Les journées du plan qui recevraient un type.
    ///
    /// Bornées au plan lui-même, du premier jour prévu au dernier : au-delà,
    /// « aucune séance » ne veut pas dire « repos », mais « on ne sait pas ».
    /// C'est ce qui empêche la déduction de peindre en jour de repos toute
    /// l'histoire de la bibliothèque et tout l'avenir.
    ///
    /// Une journée déjà réglée est écartée ici, avant l'aperçu : la règle du
    /// non-écrasement doit se voir, pas seulement s'appliquer.
    static func propositions(
        dans context: ModelContext, calendar: Calendar = .current
    ) throws -> [Proposition] {
        let seances = try context.fetch(
            FetchDescriptor<PlannedSession>(sortBy: [SortDescriptor(\.dateKeyRaw)])
        )
        guard let premier = seances.first?.dateKey,
              let dernier = seances.last?.dateKey
        else { return [] }

        let types = try context.fetch(FetchDescriptor<DayType>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard !types.isEmpty else { return [] }

        var parJour: [String: [PlannedSession]] = [:]
        for seance in seances { parJour[seance.dateKeyRaw, default: []].append(seance) }

        var dejaReglees: Set<String> = []
        for journee in try context.fetch(FetchDescriptor<NutritionDay>())
        where journee.dayType != nil {
            dejaReglees.insert(journee.dateKeyRaw)
        }

        var propositions: [Proposition] = []
        var jour = premier
        while jour <= dernier {
            defer { jour = jour.advanced(by: 1, calendar: calendar) }
            guard !dejaReglees.contains(jour.raw) else { continue }

            let duJour = parJour[jour.raw] ?? []
            guard let categorie = TrainingDayTypeRule.categorie(
                pour: duJour.map {
                    TrainingDayTypeRule.Seance(
                        sport: $0.sport, titre: $0.title,
                        duree: $0.plannedDuration, distance: $0.plannedDistance
                    )
                }
            ) else { continue }
            guard let type = TrainingDayTypeRule.type(categorie, parmi: types, nom: \.name)
            else { continue }

            propositions.append(Proposition(
                dateKey: jour, type: type,
                resume: duJour.isEmpty
                    ? "Aucune séance"
                    : duJour.map { $0.title.isEmpty ? $0.sport.displayName : $0.title }
                        .joined(separator: " · ")
            ))
        }
        return propositions
    }

    /// Écrit les propositions retenues. Rend combien de journées ont changé.
    @discardableResult
    static func ecrire(
        _ propositions: [Proposition], dans context: ModelContext
    ) throws -> Int {
        var existantes: [String: NutritionDay] = [:]
        for journee in try context.fetch(FetchDescriptor<NutritionDay>()) {
            existantes[journee.dateKeyRaw] = journee
        }

        var posees = 0
        for proposition in propositions {
            if let journee = existantes[proposition.dateKey.raw] {
                // Le garde-fou une seconde fois : l'aperçu a pu vieillir entre
                // son calcul et le clic.
                guard journee.dayType == nil else { continue }
                journee.dayType = proposition.type
            } else {
                context.insert(NutritionDay(
                    dateKey: proposition.dateKey, dayType: proposition.type
                ))
            }
            posees += 1
        }
        try context.save()
        return posees
    }
}
