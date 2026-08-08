// Cairn/Features/Nutrition/RecipePickerSheet.swift
import SwiftUI
import SwiftData

/// Applies one recipe to one meal — the whole recipe lands as entries in a
/// single gesture, then the sheet closes.
struct RecipePickerSheet: View {
    let slot: MealSlot
    let dateKey: DateKey

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var selectedID: PersistentIdentifier?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Charger une recette dans \(slot.name)")
                .font(.headline)
            if recipes.isEmpty {
                ContentUnavailableView(
                    "Aucune recette",
                    systemImage: "book",
                    description: Text(
                        "« Enregistrer ce repas comme recette » en crée une "
                        + "depuis un repas rempli."
                    )
                )
            } else {
                List(recipes, selection: $selectedID) { recipe in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name).lineLimit(1)
                        Text(subtitle(of: recipe))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(recipe.persistentModelID)
                }
                .frame(minHeight: 200)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Appliquer") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 340)
    }

    private func subtitle(of recipe: Recipe) -> String {
        let items = recipe.orderedItems
        let kcal = items.map { Macros(of: $0).kcal }.reduce(0, +)
        let count = items.count
        let plural = count > 1 ? "s" : ""
        var parts = ["\(count) aliment\(plural)", "\(Int(kcal.rounded())) kcal"]
        if let slotName = recipe.mealSlot?.name { parts.append(slotName) }
        return parts.joined(separator: " · ")
    }

    private func apply() {
        guard let recipe = recipes.first(
            where: { $0.persistentModelID == selectedID }
        ) else { return }
        do {
            try NutritionJournal.applyRecipe(
                recipe, to: dateKey, slot: slot, in: modelContext
            )
            dismiss()
        } catch {
            errorMessage =
                "La recette n'a pas pu être appliquée. \(error.localizedDescription)"
        }
    }
}
