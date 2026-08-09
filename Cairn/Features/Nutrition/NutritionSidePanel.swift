import SwiftUI
import SwiftData

/// The detail column beside the journal screens: suivinut's side panel —
/// mini calendar on top, the 7-day / weight / regularity stats below.
struct NutritionSidePanel: View {
    @Binding var selected: DateKey

    @Query private var entries: [FoodEntry]
    @Query(sort: \WeightEntry.dateKeyRaw) private var weights: [WeightEntry]
    @AppStorage(NutritionSettings.weightGoalKey)
    private var weightGoal = NutritionSettings.defaultWeightGoalKg

    var body: some View {
        let model = NutritionSidePanelModel.compute(
            entries: entries, weights: weights,
            goalKg: weightGoal, day: selected
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MiniCalendarView(selected: $selected, loggedDays: model.loggedDays)
                Divider()
                section("Apports · 7 j") {
                    statLine("moy. \(model.averageKcal7d) kcal/j")
                    statLine("moy. \(model.averageProtein7d) g P/j")
                }
                section("Poids") {
                    if let last = model.lastWeightKg {
                        statLine(
                            "\(Format.typedNumber(last)) kg · obj "
                            + "\(Format.typedNumber(weightGoal))"
                        )
                        if let delta = model.weightDelta7d {
                            coloredLine(
                                "vs il y a 7 j : \(Format.signedTwoDecimals(delta)) kg",
                                favorable: delta <= 0
                            )
                        }
                        if let rate = model.weightRatePerWeek {
                            coloredLine(
                                "\(Format.signedTwoDecimals(rate)) kg/sem",
                                favorable: rate <= 0
                            )
                        }
                        if let weeks = model.weeksToGoal {
                            statLine("→ obj : ~\(Int(weeks.rounded())) sem")
                        }
                    } else {
                        statLine("aucune pesée")
                    }
                }
                section("Régularité") {
                    statLine(
                        "\(model.loggedThisMonth)/\(model.daysElapsedThisMonth) j ce mois"
                    )
                    statLine("série \(model.streak) j")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            content()
        }
    }

    private func statLine(_ text: String) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    /// Green when the trend serves the goal, red otherwise — the one colour
    /// rule suivinut's panel uses.
    private func coloredLine(_ text: String, favorable: Bool) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(favorable ? .green : .red)
    }
}
