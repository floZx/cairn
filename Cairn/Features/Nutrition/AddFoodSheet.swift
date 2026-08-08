// Cairn/Features/Nutrition/AddFoodSheet.swift
import SwiftUI
import SwiftData

/// Adding one food to one meal — a thin shell over `FoodPickerView`: the
/// picker chooses the food, this sheet decides it becomes a journal entry.
struct AddFoodSheet: View {
    let slot: MealSlot
    let dateKey: DateKey

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajouter à \(slot.name)")
                .font(.headline)
            FoodPickerView { pick in add(pick) }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 460)
    }

    private func add(_ pick: FoodPick) {
        do {
            try NutritionJournal.addEntry(
                in: modelContext, dateKey: dateKey, slot: slot,
                foodName: pick.foodName, kcal100: pick.kcal100,
                protein100: pick.protein100, carbs100: pick.carbs100,
                fat100: pick.fat100, grams: pick.grams,
                productCode: pick.productCode
            )
            dismiss()
        } catch {
            errorMessage =
                "Votre ajout n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }
}
