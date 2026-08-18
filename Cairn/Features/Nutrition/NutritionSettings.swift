// Cairn/Features/Nutrition/NutritionSettings.swift
import Foundation

/// AppStorage keys for the nutrition targets — held here so no key literal
/// is ever duplicated, the same rule as `StatsPeriod.storageKey`. Defaults
/// match suivinut's seed; a suivinut import overwrites them with the
/// journal's own values.
enum NutritionSettings {
    static let proteinTargetKey = "nutritionProteinTargetG"
    static let fatTargetKey = "nutritionFatTargetG"
    static let weightGoalKey = "nutritionWeightGoalKg"
    /// Les fibres du jour, en grammes.
    ///
    /// Un seul chiffre, global, à côté des protéines et des lipides plutôt que
    /// sur le type de journée : un jour de repos et une sortie longue
    /// demandent les mêmes fibres. Les calories, elles, suivent
    /// l'entraînement, d'où leur place sur `DayType`.
    static let fiberTargetKey = "nutritionFiberTargetG"

    static let defaultProteinTargetG = 130.0
    static let defaultFatTargetG = 66.0
    static let defaultWeightGoalKg = 70.0
    /// Trente grammes : le repère de l'ANSES pour un adulte. L'EFSA retient
    /// vingt-cinq comme apport satisfaisant ; c'est le plus exigeant des deux
    /// qui sert de valeur de départ, et il se change dans les réglages.
    static let defaultFiberTargetG = 30.0
}
