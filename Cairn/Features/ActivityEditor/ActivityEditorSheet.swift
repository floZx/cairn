import SwiftUI

/// The one form for editing an activity and for creating one.
///
/// A modal sheet rather than inline fields, for a reason that is not cosmetic:
/// an explicit Save is what tells us which fields the user actually meant to
/// change, which is exactly what `editedFields` must contain. Inline editing
/// would freeze a field on a stray keystroke.
struct ActivityEditorSheet: View {
    enum Mode {
        case edit(Activity)
        case create
    }

    let mode: Mode
    /// Whether to open with the cursor already in the note field.
    var focusesNotes: Bool = false
    let onSave: (ActivityDraft) -> Void

    @State private var draft: ActivityDraft
    /// Whether the note field is showing its rendering rather than its source.
    @State private var showsNotePreview = false
    @FocusState private var notesFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        mode: Mode, focusesNotes: Bool = false,
        onSave: @escaping (ActivityDraft) -> Void
    ) {
        self.mode = mode
        self.focusesNotes = focusesNotes
        self.onSave = onSave
        switch mode {
        case let .edit(activity):
            _draft = State(initialValue: ActivityDraft(activity))
        case .create:
            _draft = State(initialValue: ActivityDraft(startingOn: Date()))
        }
    }

    private func save() {
        guard draft.validationMessage == nil else { return }
        onSave(draft)
        dismiss()
    }

    private var title: String {
        switch mode {
        case .edit: "Modifier l'activité"
        case .create: "Nouvelle activité"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.navigationTitle` has no effect on a macOS sheet with no
            // navigation bar to put it in — the title landed nowhere. Its own
            // `VStack` in the sheet's header is what actually shows it.
            VStack(alignment: .leading) {
                Text(title)
                    .font(.title2.bold())
            }
            .padding([.top, .horizontal])
            .padding(.bottom, 4)

            Form {
                Section {
                    TextField("Nom", text: $draft.name)
                    Picker("Sport", selection: $draft.sport) {
                        ForEach(SportType.allCases) { sport in
                            SportLabel(sport.displayName, sport: sport)
                                .tag(sport)
                        }
                    }
                    // Read on the activity's own clock: a picker formats and
                    // parses in a time zone, and the environment's is this
                    // Mac's. Left alone, an outing recorded in Paris opened
                    // two hours late here in summer, and saving moved it.
                    DatePicker("Date", selection: $draft.startDate)
                        .environment(\.timeZone, draft.timeZone)
                }

                Section("Chiffres") {
                    OptionalNumberField(
                        title: "Distance", unit: "km",
                        value: Binding(
                            get: { draft.distanceKm == 0 ? nil : draft.distanceKm },
                            set: { draft.distanceKm = $0 ?? 0 }
                        )
                    )
                    OptionalNumberField(
                        title: "Durée", unit: "min",
                        value: Binding(
                            get: { draft.movingMinutes == 0 ? nil : draft.movingMinutes },
                            set: { draft.movingMinutes = $0 ?? 0 }
                        )
                    )
                    OptionalNumberField(
                        title: "D+", unit: "m",
                        value: Binding(
                            get: { draft.elevationGain == 0 ? nil : draft.elevationGain },
                            set: { draft.elevationGain = $0 ?? 0 }
                        )
                    )
                }

                Section {
                    // Taller than the fields above on purpose: the size of a box
                    // is what says how much is expected in it, and a two-line
                    // note field asks for two lines.
                    if showsNotePreview {
                        ScrollView {
                            // The same size and the same tag rendering as the
                            // detail pane: a preview that renders differently
                            // from the thing it previews is worse than none.
                            MarkdownText(
                                markdown: draft.notes,
                                baseSize: ActivityDetailView.noteSize,
                                hidesTagHashes: true
                            )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                        .frame(minHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                    } else {
                        // First `TextEditor` in the project, so no house style to
                        // follow — and it arrives borderless, which reads as
                        // nothing at all beside the bordered fields above it.
                        TextEditor(text: $draft.notes)
                            .citations($draft.notes)
                            .font(.body)
                            .focused($notesFocused)
                            .frame(minHeight: 150)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: .separatorColor))
                            )
                    }
                } header: {
                    HStack {
                        Text("Notes")
                        Spacer()
                        Picker("", selection: $showsNotePreview) {
                            Text("Écrire").tag(false)
                            Text("Aperçu").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                        // Nothing to preview yet, and an empty preview pane is a
                        // worse first impression than no choice at all.
                        .disabled(draft.notes.isEmpty)
                    }
                } footer: {
                    Text(
                        "Markdown : **gras**, *italique*, # titre, - liste, > citation."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Type de séance", selection: $draft.workoutLabel) {
                        Text("Aucun").tag(ActivityLabel?.none)
                        ForEach(ActivityLabel.workoutTypes) { label in
                            GutteredLabel(label.displayName, systemImage: label.symbolName)
                                .tag(ActivityLabel?.some(label))
                        }
                    }
                    Toggle("Domicile-travail", isOn: $draft.isCommute)
                    Toggle("Home-trainer", isOn: $draft.isTrainer)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                // The reason rather than a greyed-out button with no explanation.
                if let message = draft.validationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.validationMessage != nil)
                    .help("Enregistrer (⌘⏎)")

                // A twin, invisible, carrying ⌘⏎. `defaultAction` is Return, and
                // a `TextEditor` keeps Return for itself to make a new line — so
                // from the note field, the only field anyone stays in for long,
                // nothing validated the form at all. SwiftUI takes one shortcut
                // per button, hence two buttons for one action.
                Button("", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.validationMessage != nil)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .padding(12)
        }
        .frame(width: 520, height: 680)
        .onAppear {
            // Only ever moves focus *into* the notes: leaving it alone otherwise
            // keeps the name field first, which is what a new activity needs.
            if focusesNotes { notesFocused = true }
        }
    }
}

extension ActivityEditorSheet.Mode: Identifiable {
    var id: String {
        switch self {
        case let .edit(activity): "edit-\(activity.uuid)"
        case .create: "create"
        }
    }
}

extension ActivityEditorSheet.Mode {
    /// Writes a saved draft onto the activity being edited, or turns it into a
    /// freshly made one for the caller to insert.
    ///
    /// Pulled out of the sheet's `onSave` closure so this switch — the one
    /// place that decides which of `ActivityDraft`'s two write paths runs — is
    /// reachable from a test. A closure captured by `.sheet(item:)` is not.
    func apply(_ draft: ActivityDraft) -> Activity {
        switch self {
        case let .edit(activity):
            draft.apply(to: activity)
            return activity
        case .create:
            return draft.makeActivity()
        }
    }
}
