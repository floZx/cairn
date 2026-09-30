// Cairn/Features/Nutrition/WeightEntrySheet.swift
import SwiftUI
import SwiftData

/// The weigh-in of one day: kilograms and an optional note. The day is the
/// one the nutrition screen shows — no date picker; to reach another day, one
/// moves the screen, or clicks it on the weight chart.
struct WeightEntrySheet: View {
    let dateKey: DateKey
    let existing: WeightEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var weightKg: Double
    @State private var note: String
    @State private var errorMessage: String?
    @FocusState private var weightFocused: Bool

    init(dateKey: DateKey, existing: WeightEntry?, defaultWeightKg: Double) {
        self.dateKey = dateKey
        self.existing = existing
        _weightKg = State(initialValue: existing?.weightKg ?? defaultWeightKg)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pesée du \(Format.dateOnly(dateKey.date()))")
                .font(.headline)
            HStack(spacing: 8) {
                Text("Poids")
                DecimalField(
                    placeholder: "kg", value: $weightKg, width: 80,
                    focus: $weightFocused
                )
                Text("kg")
            }
            TextField("Note (optionnelle)", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                if existing != nil {
                    Button("Supprimer", role: .destructive) { delete() }
                }
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(weightKg <= 0)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onAppear { weightFocused = true }
    }

    private func save() {
        do {
            try NutritionJournal.recordWeight(
                weightKg, note: note, for: dateKey, in: modelContext
            )
            dismiss()
        } catch {
            errorMessage =
                "La pesée n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    private func delete() {
        guard let existing else { return }
        do {
            try GarminWeightImporter.delete(existing, in: modelContext)
            dismiss()
        } catch {
            errorMessage =
                "La pesée n'a pas pu être supprimée. \(error.localizedDescription)"
        }
    }
}
