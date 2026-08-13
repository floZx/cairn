// Cairn/Features/Nutrition/WeightEntrySheet.swift
import SwiftUI
import SwiftData

/// One weigh-in: date, kilograms, optional note. Editing re-records on the
/// chosen day (one weigh-in per day, re-entry replaces); moving an existing
/// entry to another day deletes the original row.
struct WeightEntrySheet: View {
    let existing: WeightEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var weightKg: Double
    @State private var note: String
    @State private var errorMessage: String?
    @FocusState private var weightFocused: Bool

    init(existing: WeightEntry?, defaultWeightKg: Double) {
        self.existing = existing
        _date = State(initialValue: existing?.dateKey?.date() ?? Date())
        _weightKg = State(initialValue: existing?.weightKg ?? defaultWeightKg)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "Nouvelle pesée" : "Modifier la pesée")
                .font(.headline)
            DatePicker(
                "Date", selection: $date, in: ...Date(),
                displayedComponents: .date
            )
            HStack(spacing: 8) {
                Text("Poids")
                DecimalField(
                    placeholder: "kg", value: $weightKg, width: 80,
                    focus: $weightFocused
                )
                Text("kg")
            }
            TextField("Note (optionnelle)", text: $note)
                .textFieldStyle(.roundedBorder)
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
                    .disabled(weightKg <= 0)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onAppear { weightFocused = true }
    }

    private func save() {
        let key = DateKey(date)
        do {
            try NutritionJournal.recordWeight(
                weightKg, note: note, for: key, in: modelContext
            )
            // Moving an entry to another day: the upsert above created (or
            // replaced) the target day — the original row must not linger.
            if let existing, !existing.isDeleted, existing.dateKeyRaw != key.raw {
                try NutritionJournal.deleteWeight(existing, in: modelContext)
            }
            dismiss()
        } catch {
            errorMessage =
                "La pesée n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
