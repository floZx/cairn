// Cairn/Features/Nutrition/MealNoteSheet.swift
import SwiftUI
import SwiftData

/// One free-form note per (day, meal). Saving an emptied note deletes it —
/// an empty note is not a note.
struct MealNoteSheet: View {
    let slot: MealSlot
    let dateKey: DateKey
    let existingNote: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?
    @FocusState private var noteFocused: Bool

    init(slot: MealSlot, dateKey: DateKey, existingNote: String?) {
        self.slot = slot
        self.dateKey = dateKey
        self.existingNote = existingNote
        _text = State(initialValue: existingNote ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note — \(slot.name)")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .focused($noteFocused)
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
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
        .onAppear { noteFocused = true }
    }

    private func save() {
        do {
            try NutritionJournal.setMealNote(
                text, for: dateKey, slot: slot, in: modelContext
            )
            dismiss()
        } catch {
            errorMessage =
                "La note n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
