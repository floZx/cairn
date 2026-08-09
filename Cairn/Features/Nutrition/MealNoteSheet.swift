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
                    .help("Enregistrer (⌘⏎)")

                // A twin, invisible, carrying ⌘⏎. `defaultAction` is Return, and
                // a `TextEditor` keeps Return for itself to make a new line — so
                // from the note field, the only field anyone stays in for long,
                // nothing validated the form at all. SwiftUI takes one shortcut
                // per button, hence two buttons for one action.
                Button("") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
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
