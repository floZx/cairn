// Cairn/Features/Nutrition/WeightPeriod.swift
import Foundation

/// The chart window. Persisted so the screen reopens the way it was left —
/// same rule as `StatsPeriod`.
enum WeightPeriod: String, CaseIterable, Identifiable {
    case thirtyDays
    case ninetyDays
    case year
    case all

    static let storageKey = "weightPeriod"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .thirtyDays: return "30 j"
        case .ninetyDays: return "90 j"
        case .year: return "1 an"
        case .all: return "Tout"
        }
    }

    /// nil = no cutoff, every weigh-in.
    var days: Int? {
        switch self {
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}
