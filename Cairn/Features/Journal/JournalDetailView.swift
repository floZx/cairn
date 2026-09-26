import AppKit
import SwiftUI
import UniformTypeIdentifiers
// For `PersistentIdentifier` alone: the note itself is a file, and nothing in
// this view touches the database. It is how the day's outings are named on the
// way back to `RootView`.
import SwiftData

/// The note, read as Markdown and edited on a click.
///
/// The pane opens on the note rendered — titles, lists, quotes, through the
/// same `MarkdownText` that serves the notes of an activity — and turns into a
/// plain text field as soon as one clicks into it, or presses `e`, `n` or `⏎`
/// from the list. Escape hands the note back, rendered.
///
/// The first version was a text field and nothing else, on the grounds that a
/// journal exists to be written in and a preview puts a keystroke between the
/// thought and the page. Using it settled the question the other way: a journal
/// is re-read far more often than it is written, and the `#` and the `-` in
/// front of every line are noise on the days one only reads. Writing still
/// costs one click, or the key one already presses to write.
///
/// Going from rendered to editor does not put the caret where the click landed:
/// they are two different views, and SwiftUI carries no click position from one
/// to the other. It lands at the *end* of the text — what `TextEditor` does when
/// `@FocusState` reaches it, observed at the keyboard. A text *replaced* from
/// outside leaves the caret there too, which is why the draft below is never
/// replaced under the typing: that is the same end-of-text jump, but arriving
/// on every keystroke.
struct JournalDetailView: View {
    /// The note's text size, in both modes.
    ///
    /// Two points above the system body, which is 13 here. A journal note has
    /// the pane to itself and is read for minutes at a stretch, unlike an
    /// activity's note, which is one field among the figures and keeps the
    /// system size.
    static let noteSize: CGFloat = 17
    /// About one and a half lines: a page read for minutes, not a label.
    static let noteLineSpacing: CGFloat = 8
    /// About sixty-four characters of New York at 17 pt: past that, the eye
    /// loses the start of the next line.
    static let textWidth: CGFloat = 600
    /// The side margins of the heading, the cards and the text alike.
    static let margin: CGFloat = 40

    /// The day this pane is about: the vault's note for it, and what was
    /// written about it elsewhere. The tags shown are the day's, every
    /// source together.
    let day: JournalDay
    /// The store's text for this note: what the reader renders, and what the
    /// draft is seeded from. Never what the editor is bound to — see `draft`.
    let text: String
    /// Moves when the store replaced that text itself rather than took it from
    /// here. The signal the draft waits for.
    let textRevision: Int
    var focusRequest: Int
    /// The editor is taking this note's text: the store holds the day open
    /// from here on, so its row survives a folder event and a change arriving
    /// from the phone reaches the editor instead of being written over.
    let onBeginEditing: () -> Void
    let onEdit: (String) -> Void
    let onSelectTag: (JournalTag) -> Void
    /// Opening one of the day's outings, which leaves the journal for the
    /// section that can actually show a map and a set of charts.
    let onSelectActivity: (PersistentIdentifier) -> Void
    let onLeaveEditor: () -> Void
    /// Aller à la journée des repas depuis son récap.
    let onSelectDay: (DateKey) -> Void
    /// Aller au poids depuis le récap d'une pesée.
    let onSelectWeight: () -> Void
    /// Where a note's pictures resolve to: the attachment cache, which always
    /// exists. It used to be the vault, and nil until a folder was chosen —
    /// hence the disabled button and the refused drops this view no longer
    /// has any reason to make.
    let attachmentsBase: URL
    /// The files a gesture produced, in the order they arrived. This view only
    /// gathers them; taking them into the base and writing the line belongs to
    /// whoever holds the store.
    let onAddPhotos: ([URL]) -> Void
    /// The same for pasted bytes, which carry no file at all — a screenshot is
    /// an image on the clipboard and nothing more.
    let onPastePhoto: (Data) -> Void

    /// Vrai quand l'éditeur doit avoir le clavier. Un état ordinaire et non
    /// un `@FocusState` : c'est `NoteTextView` qui tient le premier
    /// répondant, et les deux mécaniques ne se parlent pas.
    @State private var editorFocused = false
    /// Reading or writing, and on which note. The rules are `JournalEditing`'s,
    /// and tested there: what is left here is the focus plumbing.
    @State private var editing = JournalEditing()
    /// The text the editor holds, which the editor owns while it holds it.
    ///
    /// It used to be bound straight to the store — `Binding(get: { text },
    /// set: onEdit)` — and every keystroke went through `update(_:for:)`,
    /// which rebuilds `notes`, which this pane's parent reads, so the body ran
    /// again and handed `TextEditor` its string back. A `TextEditor` whose
    /// bound value is replaced from outside loses its selection: the letter
    /// was typed where the caret was, then the caret jumped to the end of the
    /// note. Correcting a sentence — most of what a journal is — was
    /// impossible.
    ///
    /// So the text lives here while it is being typed, and goes *out* to the
    /// store on every keystroke: the row's excerpt, the tags, the tag counts
    /// in the sidebar and the reconciliation all still follow the typing
    /// rather than the debounce. What does not happen is the read back.
    ///
    /// It is seeded on the three transitions where the store's copy is the one
    /// to show, and only there: entering the editor, another note arriving in
    /// the pane, and the store saying it replaced the text itself
    /// (`textRevision`) — an external change adopted on a note with nothing
    /// unsaved, or **Recharger**.
    @State private var draft = ""

    var body: some View {
        photoGestures(
            // Reading scrolls the whole page, heading included; writing keeps
            // the heading above the editor, which scrolls on its own.
            Group {
                if editing.isEditing(day.id) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        editor
                    }
                } else {
                    reader
                }
            }
        )
        // `e`, `n`, `⏎` from the list and ⌘N all land in the field: reading
        // mode holds no focus of its own, so nothing swallows them on the way.
        .onChange(of: focusRequest) { _, _ in beginEditing() }
        // The note just left goes back to reading, under `JournalEditing`'s
        // rule rather than this view's. The focus goes with it: left standing
        // at true with no field on screen, it would make the next request a
        // no-op and the next note would not get the keyboard.
        .onChange(of: day.id) { previous, _ in
            editing.left(previous)
            editorFocused = false
            seedDraft()
        }
        // The store replaced the text under us: an external change taken on a
        // note with nothing unsaved, or **Recharger** dropping the buffer.
        // This is the one moment the caret is allowed to move on its own —
        // the text it was in is not there any more.
        .onChange(of: textRevision) { _, _ in
            // Jamais pendant qu'on écrit.
            //
            // Le magasin publie une révision quand son texte change — y
            // compris quand c'est **notre** frappe qui vient d'y arriver.
            // Réensemencer le brouillon à ce moment-là remplace le texte sous
            // le curseur par une version d'un caractère en retard : l'éditeur
            // réécrit sa chaîne, replace le curseur au mieux, et l'on voit ce
            // qu'il a décrit — le texte qui disparaît un instant, le curseur
            // qui clignote au mauvais endroit.
            //
            // Ce qu'on tape est la vérité tant qu'on tape. Une modification
            // venue d'ailleurs attendra que le champ soit rendu — et le
            // changement de jour, lui, passe par un autre chemin.
            guard !editorFocused else { return }
            seedDraft()
            // And we are still the ones holding it. Some of the reasons the
            // store replaces a text are also reasons it stops considering the
            // note open — dropping the buffer clears that — while this pane
            // stays exactly where it is, editor and caret included. Saying so
            // again costs nothing when the store already knows, and is what
            // keeps the rule true for the paths that rebuild no view: the same
            // folder chosen a second time is one of them.
            if editing.isEditing(day.id) { onBeginEditing() }
        }
    }

    /// Takes the store's text, unless the editor already holds exactly it.
    ///
    /// The comparison is not an optimisation: seeding an identical string is
    /// still a value replaced from outside as far as `TextEditor` is
    /// concerned, and the caret would move for nothing.
    private func seedDraft() {
        if draft != text { draft = text }
    }

    /// The day's heading, then what it did.
    ///
    /// The pane had no heading: a date in body type over two grey blocks and
    /// a rule. Now the title and the line under it, on a very pale warm
    /// wash — the activity pane's lit heading, a good deal quieter — and the
    /// day's outings and meals as cards, as an activity shows its gear and
    /// weather.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            JournalDayHeading(
                date: day.date, tags: day.tags,
                onSelectTag: onSelectTag, onAddPhotos: choosePhotos
            )
            JournalDayCards(
                date: day.date,
                onSelectActivity: onSelectActivity,
                onSelectDay: onSelectDay,
                onSelectWeight: onSelectWeight
            )
            .padding(.horizontal, Self.margin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Files dropped anywhere on the pane, and pictures pasted into it.
    ///
    /// On the whole pane rather than on the editor: one drops a photo on a
    /// note, not into a paragraph, and the line lands at the end either way.
    private func photoGestures(_ content: some View) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                onAddPhotos(urls)
                return true
            }
            .onPasteCommand(of: [.fileURL, .png, .jpeg, .heic]) { providers in
                paste(providers)
            }
    }

    /// One picture per paste, whatever the clipboard offers.
    ///
    /// The clipboard describes the same image several ways at once — a file
    /// URL, a PNG, a JPEG — and asking for all of them hands back one provider
    /// each. Treating every provider as a photo wrote the same screenshot
    /// twice: found in the vault on 13 August 2026 as a 1.6 MB `.png` and a
    /// 437 kB `.jpg`, one second apart.
    ///
    /// Files win when there are any: keeping what the Finder had beats
    /// re-encoding a copy of it. Failing that, the first form that carries
    /// bytes, and only the first.
    private func paste(_ providers: [NSItemProvider]) {
        let files = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        if !files.isEmpty {
            for provider in files {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in onAddPhotos([url]) }
                }
            }
            return
        }
        for type in [UTType.png, .jpeg, .heic] {
            guard let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(type.identifier)
            }) else { continue }
            provider.loadDataRepresentation(
                forTypeIdentifier: type.identifier
            ) { data, _ in
                guard let data else { return }
                Task { @MainActor in onPastePhoto(data) }
            }
            return
        }
    }

    /// The file panel, for the button.
    private func choosePhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.prompt = "Ajouter"
        panel.message = "Choisissez les photos à ajouter à cette note"
        guard panel.runModal() == .OK else { return }
        onAddPhotos(panel.urls)
    }

    /// The note as one reads it.
    ///
    /// The whole surface takes the click, not only the text: an empty note has
    /// nothing to aim at, and a note of three lines leaves most of the pane
    /// looking dead. The invitation is there for the empty one — a blank pane
    /// that turns into an editor when clicked says so nowhere.
    private var reader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Group {
                    if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Cliquez pour écrire")
                            .font(.system(size: Self.noteSize, design: .serif))
                            .foregroundStyle(.tertiary)
                    } else {
                        MarkdownText(
                            markdown: bodyText,
                            baseSize: Self.noteSize,
                            hidesTagHashes: true,
                            attachmentsBase: attachmentsBase,
                            design: .serif,
                            lineSpacing: Self.noteLineSpacing
                        )
                    }
                }
                .frame(maxWidth: Self.textWidth, alignment: .leading)
                .padding(.horizontal, Self.margin)
                .padding(.top, 24)
                .padding(.bottom, 12)
                // The text itself, whatever height it happens to have…
                .contentShape(.rect)
                .onTapGesture { beginEditing() }
                // …and room under it, which is most of the pane on most days.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .contentShape(.rect)
                    .onTapGesture { beginEditing() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A new scroll view per note: kept as one, a long note read to the end
        // would hand the next one its own offset, which opens somewhere in the
        // middle of a note one has never seen.
        .id(day.id)
    }

    /// What gets rendered: the buffer on screen, front matter left out.
    ///
    /// The buffer rather than the note's text, so leaving the editor shows what was
    /// just typed and not what the file said before the save.
    private var bodyText: String { JournalFileNote.body(of: text) }

    /// Reading to writing.
    ///
    /// The focus is claimed one tick later: the field does not exist yet in
    /// this update pass, and `@FocusState` set before its view is inserted does
    /// not stick — the same reason `RootView` defers its own bump after opening
    /// today's note.
    private func beginEditing() {
        // The store's text, as of now: it may well have moved while the note
        // was merely being read, and the draft is only ever seeded here, on a
        // change of note, and on `textRevision`.
        seedDraft()
        onBeginEditing()
        editing.requested(for: day.id)
        Task { @MainActor in editorFocused = true }
    }

    private var editor: some View {
        // Explicit closure rather than `set: onEdit`: passing the stored
        // closure straight in converts a non-Sendable function value into the
        // `@Sendable` one `Binding` asks for, which Swift 6 warns about.
        //
        // One way only. The getter reads the draft this view holds, never the
        // store, so nothing the store does to `notes` while a key is being
        // pressed can replace the text under the caret — see `draft`.
        CompletingNoteEditor(
            texte: Binding(
                get: { draft },
                set: { nouveau in
                    guard nouveau != draft else { return }
                    draft = nouveau
                    onEdit(nouveau)
                }
            ),
            // La même taille que la lecture, et c'est tout l'intérêt : les
            // deux modes s'échangent sous le pointeur, et un texte qui
            // grandirait ou rétrécirait au clic ferait de l'échange la chose
            // qu'on remarque.
            taille: Self.noteSize,
            serif: true,
            interligne: Self.noteLineSpacing,
            focus: $editorFocused,
            onEchappement: {
                editorFocused = false
                editing.ended()
                onLeaveEditor()
            },
            onImageCollee: { data in
                onPastePhoto(data)
                return true
            }
        )
        // Where the reading text stands, less the editor's own inset: the
        // two modes swap under the pointer, and a text that jumped sideways
        // at the click would make the swap the thing one notices.
        .frame(maxWidth: Self.textWidth + 16)
        .padding(.horizontal, Self.margin - 8)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// « Samedi 26 septembre », and under it « 2026 · aujourd'hui · 2
/// activités » — on a wash of warm paper fading into the pane.
private struct JournalDayHeading: View {
    let date: DateKey
    let tags: Set<JournalTag>
    let onSelectTag: (JournalTag) -> Void
    let onAddPhotos: () -> Void

    @Query private var activities: [Activity]
    @Environment(\.colorScheme) private var colorScheme

    init(
        date: DateKey, tags: Set<JournalTag>,
        onSelectTag: @escaping (JournalTag) -> Void, onAddPhotos: @escaping () -> Void
    ) {
        self.date = date
        self.tags = tags
        self.onSelectTag = onSelectTag
        self.onAddPhotos = onAddPhotos
        let (start, end) = JournalDayActivities.dayRange(date)
        _activities = Query(filter: #Predicate<Activity> { $0.startDate >= start && $0.startDate < end })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(JournalRowLayout.title(for: date))
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                // The one gesture that shows itself: a drop and a paste are
                // both things one has to already know about.
                Button(action: onAddPhotos) {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Ajouter une photo à cette note")
            }
            HStack(spacing: 8) {
                Text(JournalRowLayout.subtitle(for: date, activities: activities.count))
                    .foregroundStyle(.secondary)
                ForEach(tags.sorted()) { tag in
                    JournalTagChip(tag: tag) { onSelectTag(tag) }
                }
            }
            .font(.callout)
        }
        .padding(.horizontal, JournalDetailView.margin)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash)
    }

    /// Paper, barely: Florian found every first version too strong, so this
    /// one starts under what would look right, and fades to nothing.
    private var wash: some View {
        let paper = colorScheme == .dark
            ? Color(red: 0.165, green: 0.149, blue: 0.129).opacity(0.55)
            : Color(red: 0.984, green: 0.961, blue: 0.925).opacity(0.7)
        return LinearGradient(colors: [paper, paper.opacity(0)], startPoint: .top, endPoint: .bottom)
    }
}
