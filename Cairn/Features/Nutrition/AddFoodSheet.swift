// Cairn/Features/Nutrition/AddFoodSheet.swift
import SwiftUI
import SwiftData

/// Adding one food to one meal — a thin shell over `FoodPickerView`: the
/// picker chooses the food, this sheet decides it becomes a journal entry.
struct AddFoodSheet: View {
    let slot: MealSlot
    let dateKey: DateKey
    /// The row the new food goes under, when one is selected in this meal.
    var after: FoodEntry?
    /// The entry that was just written, so the caller can put the cursor on
    /// it: without that, a second food added straight after would go *above*
    /// the first, the anchor never having moved.
    var onAdded: (FoodEntry) -> Void = { _ in }

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
            let entry = try NutritionJournal.addEntry(
                in: modelContext, dateKey: dateKey, slot: slot,
                foodName: pick.foodName, kcal100: pick.kcal100,
                protein100: pick.protein100, carbs100: pick.carbs100,
                fat100: pick.fat100, grams: pick.grams,
                productCode: pick.productCode, after: after
            )
            onAdded(entry)
            dismiss()
        } catch {
            errorMessage =
                "Votre ajout n'a pas pu être enregistré. \(error.localizedDescription)"
        }
    }
}
