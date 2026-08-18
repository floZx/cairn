// Cairn/Features/Nutrition/MacroGauge.swift
import SwiftUI

/// One "consumed / target" figure with a thin progress bar — the unit of
/// the day's summary row. System colours only, and the same four states a
/// meal's line carries: grey while the day is still being built, green once
/// the target is within a tenth, orange while it is still close above it,
/// red once frankly blown.
struct MacroGauge: View {
    let title: String
    let consumed: Double
    let target: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(figure).font(.title3.monospacedDigit())
            if let target, target > 0 {
                ProgressView(value: min(consumed / target, 1))
                    .tint(gaugeColor(target: target) ?? .accentColor)
                // suivinut's « reste » line: the number the next meal is
                // actually planned against, not just a bar to squint at.
                Text(remainingLabel(target: target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(gaugeColor(target: target)
                                     .map(AnyShapeStyle.init)
                                     ?? AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nil means "nothing to say yet": the bar keeps the accent colour and the
    /// line under it stays grey.
    ///
    /// The overshoot answers first, as it does on a meal's line — a figure
    /// past its target is past it, whatever else it is, and the warning
    /// outranks the encouragement.
    private func gaugeColor(target: Double) -> Color? {
        switch NutritionMath.overshoot(consumed: consumed, target: target) {
        case .moderate: .orange
        case .heavy: .red
        case nil:
            NutritionMath.isOnTarget(consumed: consumed, target: target)
                ? .green : nil
        }
    }

    /// Derived from the rounded figures the gauge itself shows: computed on
    /// the raw values, it announced "dépassé de 1 g" under a "33 / 33 g" that
    /// exceeds nothing the reader can see.
    private func remainingLabel(target: Double) -> String {
        let remaining = target.rounded() - consumed.rounded()
        return remaining >= 0
            ? "reste \(rounded(remaining)) \(unit)"
            : "dépassé de \(rounded(-remaining)) \(unit)"
    }

    private var figure: String {
        guard let target else { return "\(rounded(consumed)) \(unit)" }
        return "\(rounded(consumed)) / \(rounded(target)) \(unit)"
    }

    private func rounded(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}

/// Les fibres du jour : un chiffre qu'on cherche à atteindre, jamais à ne pas
/// dépasser.
///
/// Sœur de `MacroGauge` plutôt que variante à drapeaux, parce que deux règles
/// changent, et ce sont les deux qui font l'intérêt de l'affaire.
///
/// D'abord la couleur. Quarante grammes de fibres pour trente visés n'est pas
/// un dépassement, c'est une bonne journée : la jauge verdit à la cible et
/// s'arrête là, là où `MacroGauge` passerait à l'orange puis au rouge.
///
/// Ensuite, et surtout, elle avoue ce qu'elle ignore. Open Food Facts ne
/// connaît les fibres que de cinq produits sur six ; un total sec afficherait
/// « 22 / 30 g » sur une journée dont trois aliments n'ont rien annoncé, ce
/// qui n'est ni vrai ni faux mais incomplet. La ligne du dessous le dit, et
/// c'est ce qui sépare un indicateur d'un chiffre décoratif.
struct FiberGauge: View {
    let tally: FiberTally
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fibres").font(.caption).foregroundStyle(.secondary)
            Text(figure).font(.title3.monospacedDigit())
            if target > 0 {
                ProgressView(value: min(tally.grams / target, 1))
                    .tint(atteint ? .green : .accentColor)
                Text(sousLigne)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(atteint
                                     ? AnyShapeStyle(.green)
                                     : AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Atteinte dès la cible, et pour toujours au-delà — la même clémence de
    /// neuf dixièmes que `NutritionMath.isOnTarget`, sans sa borne haute.
    private var atteint: Bool {
        target > 0 && tally.grams.rounded() >= (target * 0.90).rounded()
    }

    /// Un tiret quand rien n'est connu, et non « 0 ».
    ///
    /// Le chiffre affiché est une borne inférieure : « 22 » sous « 3 aliments
    /// sans donnée » se lit bien « au moins 22 ». Mais quand aucun aliment de
    /// la journée n'annonce ses fibres, « 0 » ne se lit pas comme une borne,
    /// il se lit « tu n'en as pas mangé » — ce qui est faux, et exactement le
    /// demi-mensonge que cette jauge existe pour éviter.
    private var figure: String {
        let mesure = tally.grams == 0 && tally.unknownCount > 0
            ? "—" : entier(tally.grams)
        return "\(mesure) / \(entier(target)) g"
    }

    /// Ce qui reste, ou ce qu'on ignore — jamais les deux, et le manque
    /// d'abord : un « reste 8 g » calculé sur une journée trouée dirait un
    /// chiffre précis à propos d'une somme qui ne l'est pas.
    private var sousLigne: String {
        if tally.unknownCount > 0 {
            let pluriel = tally.unknownCount > 1 ? "s" : ""
            return "\(tally.unknownCount) aliment\(pluriel) sans donnée"
        }
        let reste = target.rounded() - tally.grams.rounded()
        return reste > 0 ? "reste \(entier(reste)) g" : "objectif atteint"
    }

    private func entier(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}
