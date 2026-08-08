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

    static let defaultProteinTargetG = 130.0
    static let defaultFatTargetG = 66.0
    static let defaultWeightGoalKg = 70.0
}
