// Cairn/Features/Nutrition/CaloriesCard.swift
import SwiftUI

/// The day's calories beside the weight chart: the figure, then one bar cut
/// into the meals that filled it, over a grey track that runs to the target —
/// where a plain gauge said how much, this says from where.
///
/// Colours follow `MacroGauge`: the accent while nothing is to be said, green
/// on target, orange then red past it. The meals are that one colour at
/// falling strengths, so the bar still reads as a single gauge.
struct CaloriesCard: View {
    let meals: [NutritionDayModel.Meal]
    let consumed: Double
    let target: Double?

    /// Strength of each meal's segment, in the order of the day.
    private static let strengths: [Double] = [1, 0.72, 0.5, 0.34]

    var body: some View {
        let color = target.flatMap { MacroGauge.color(consumed: consumed, target: $0) }
            ?? .accentColor
        VStack(alignment: .leading, spacing: 6) {
            Text("Calories").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(figure).font(.title.monospacedDigit())
                Spacer()
                if let target, target > 0 {
                    Text(MacroGauge.remainingLabel(consumed: consumed, target: target, unit: "kcal"))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(MacroGauge.color(consumed: consumed, target: target)
                                         .map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                }
            }
            bar(color: color)
                .frame(height: 10)
                .padding(.top, 2)
            legend(color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eaten: [(offset: Int, meal: NutritionDayModel.Meal)] {
        Array(meals.enumerated()).filter { $0.element.consumed.kcal > 0 }
            .map { ($0.offset, $0.element) }
    }

    private func strength(_ index: Int) -> Double {
        Self.strengths[min(index, Self.strengths.count - 1)]
    }

    /// Scaled to the larger of target and total: past the target, the bar
    /// fills and the overshoot shows in its colour, not by leaving the frame.
    private func bar(color: Color) -> some View {
        GeometryReader { geometry in
            let scale = max(target ?? 0, consumed, 1)
            HStack(spacing: 1.5) {
                ForEach(eaten, id: \.meal.slotID) { item in
                    Rectangle()
                        .fill(color.opacity(strength(item.offset)))
                        .frame(width: max(0, geometry.size.width * item.meal.consumed.kcal / scale - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    private func legend(color: Color) -> some View {
        HStack(spacing: 12) {
            ForEach(eaten, id: \.meal.slotID) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(color.opacity(strength(item.offset)))
                        .frame(width: 6, height: 6)
                    Text("\(item.meal.slotName) \(Int(item.meal.consumed.kcal.rounded()))")
                        .monospacedDigit()
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var figure: String {
        let eatenText = "\(Int(consumed.rounded()))"
        guard let target else { return "\(eatenText) kcal" }
        return "\(eatenText) / \(Int(target.rounded())) kcal"
    }
}
