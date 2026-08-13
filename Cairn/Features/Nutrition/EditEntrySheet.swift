// Cairn/Features/Nutrition/EditEntrySheet.swift
import SwiftUI
import SwiftData

/// Label and grams only: the per-100 g values were captured at entry time
/// and editing them would rewrite what was actually eaten.
struct EditEntrySheet: View {
    let entry: FoodEntry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var grams: Double
    @State private var errorMessage: String?
    @FocusState private var gramsFocused: Bool

    init(entry: FoodEntry) {
        self.entry = entry
        _name = State(initialValue: entry.foodName)
        _grams = State(initialValue: entry.grams)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modifier l'aliment")
                .font(.headline)
            TextField("Nom", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("Quantité")
                DecimalField(
                    placeholder: "g", value: $grams, width: 80,
                    focus: $gramsFocused
                )
                Text("g")
                Spacer()
                Text("\(Int((entry.kcal100 * grams / 100).rounded())) kcal")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        grams <= 0
                        || name.trimmingCharacters(in: .whitespaces).isEmpty
                    )
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .onAppear { gramsFocused = true }
    }

    private func save() {
        guard !entry.isDeleted else { dismiss(); return }
        do {
            try NutritionJournal.update(
                entry,
                foodName: name.trimmingCharacters(in: .whitespaces),
                grams: grams, in: modelContext
            )
            dismiss()
        } catch {
            errorMessage =
                "Votre modification n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
