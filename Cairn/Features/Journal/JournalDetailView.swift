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
    static let noteSize: CGFloat = 15

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
    /// What the header has to say about this note, decided by `JournalNotice`
    /// rather than here: which wording, and which buttons, is the one thing in
    /// this view where being wrong loses text.
    let notice: JournalNotice?
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
    let onReloadFromDisk: () -> Void
    let onDismissConflict: () -> Void
    let onLeaveEditor: () -> Void
    /// The vault, for resolving what a note's pictures point at. Nil until a
    /// folder is chosen — the pane still reads, it simply shows no picture.
    let attachmentsBase: URL?
    /// The files a gesture produced, in the order they arrived. This view only
    /// gathers them; copying into the vault and writing the line belongs to
    /// whoever holds the store.
    let onAddPhotos: ([URL]) -> Void
    /// The same for pasted bytes, which carry no file at all — a screenshot is
    /// an image on the clipboard and nothing more.
    let onPastePhoto: (Data) -> Void

    @FocusState private var editorFocused: Bool
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
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if !day.note.isReadable {
                    unreadable
                } else if editing.isEditing(day.id) {
                    editor
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Format.fullDate(day.date.date()))
                    .font(.title3)
                Spacer()
                // The one gesture that shows itself: a drop and a paste are
                // both things one has to already know about.
                Button(action: choosePhotos) {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Ajouter une photo à cette note")
                .disabled(attachmentsBase == nil)
            }
            if !day.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(day.tags.sorted()) { tag in
                        JournalTagChip(tag: tag) { onSelectTag(tag) }
                    }
                }
            }
            // Between what identifies the note and what warns about it: the
            // day's outings and its food journal belong with the date they
            // happened on, while the banners belong as close as possible to
            // the text they are about.
            JournalDayActivities(date: day.date, onSelect: onSelectActivity)
            JournalDayNutrition(date: day.date)
            if let conflict = notice?.conflict { banner(conflict) }
            if let failure = notice?.failure { self.failure(failure) }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Files dropped anywhere on the pane, and pictures pasted into it.
    ///
    /// On the whole pane rather than on the editor: one drops a photo on a
    /// note, not into a paragraph, and the line lands at the end either way.
    private func photoGestures(_ content: some View) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                guard attachmentsBase != nil else { return false }
                onAddPhotos(urls)
                return true
            }
            .onPasteCommand(of: [.fileURL, .png, .jpeg, .heic]) { providers in
                guard attachmentsBase != nil else { return }
                paste(providers)
            }
    }

    /// A paste carrying files is a paste of those files — keeping what the
    /// finder had beats re-encoding a copy. Otherwise it is raw bytes, which
    /// is what a screenshot puts on the clipboard.
    private func paste(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in onAddPhotos([url]) }
                }
                continue
            }
            for type in [UTType.png, .jpeg, .heic]
            where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadDataRepresentation(
                    forTypeIdentifier: type.identifier
                ) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in onPastePhoto(data) }
                }
                break
            }
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
            Group {
                if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Cliquez pour écrire")
                        .font(.system(size: Self.noteSize))
                        .foregroundStyle(.tertiary)
                } else {
                    MarkdownText(
                        markdown: bodyText,
                        baseSize: Self.noteSize,
                        hidesTagHashes: true,
                        attachmentsBase: attachmentsBase
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // The text itself, whatever height it happens to have…
            .contentShape(.rect)
            .onTapGesture { beginEditing() }
        }
        // …and the space under it, which is most of the pane on most days.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .onTapGesture { beginEditing() }
        // A new scroll view per note: kept as one, a long note read to the end
        // would hand the next one its own offset, which opens somewhere in the
        // middle of a note one has never seen.
        .id(day.id)
    }

    /// What gets rendered: the buffer on screen, front matter left out.
    ///
    /// The buffer rather than the note's text, so leaving the editor shows what was
    /// just typed and not what the file said before the save.
    private var bodyText: String { JournalNote.body(of: text) }

    /// Reading to writing.
    ///
    /// The focus is claimed one tick later: the field does not exist yet in
    /// this update pass, and `@FocusState` set before its view is inserted does
    /// not stick — the same reason `RootView` defers its own bump after opening
    /// today's note. Unreadable notes are refused here rather than at each call
    /// site: `e` or Return on such a row would ask for focus nothing can take.
    private func beginEditing() {
        guard day.note.isReadable else { return }
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
        TextEditor(text: Binding(
            get: { draft },
            set: { newValue in
                guard newValue != draft else { return }
                draft = newValue
                onEdit(newValue)
            }
        ))
            // The same size as the reader, and that is the whole point: the
            // two modes swap under the pointer, and text that grew or shrank
            // on the click would make the swap the thing you notice.
            .font(.system(size: Self.noteSize))
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Escape leaves the field rather than clearing it: the note comes
            // back rendered, the list gets the keyboard back and `j`/`k` work
            // again straight away.
            .onKeyPress(.escape) {
                editorFocused = false
                editing.ended()
                onLeaveEditor()
                return .handled
            }
    }

    private var unreadable: some View {
        ContentUnavailableView(
            "Contenu illisible",
            systemImage: "exclamationmark.triangle",
            description: Text(
                """
                Ce fichier n'a pas pu être lu comme du texte. Il est laissé \
                intact : l'ouvrir ici pour écrire dessus effacerait ce qu'il \
                contient peut-être encore.
                """
            )
        )
        .frame(maxHeight: .infinity)
    }

    /// The file moved under an unsaved edit. What is on screen is the typing,
    /// never the file — losing a sentence to a sync is the one failure this
    /// whole mechanism exists to prevent.
    ///
    /// Two lines, like the failure below it: nothing writes while this is up,
    /// so the second one says what leaving the question unanswered costs.
    @ViewBuilder
    private func banner(_ conflict: JournalNotice.Conflict) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.message)
                    .font(.callout)
                Text(conflict.consequence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if conflict.offersReload {
                Button("Recharger", action: onReloadFromDisk)
            }
            Button("Garder", action: onDismissConflict)
        }
        .padding(8)
        .background(.quaternary, in: .rect(cornerRadius: 6))
    }

    /// The last save did not go through.
    ///
    /// Two lines and no buttons, deliberately: there is nothing to choose here,
    /// only something to know. The second line is the one that matters — a
    /// journal that has stopped taking a keystroke, or stopped changing note,
    /// with nothing said is read as a broken app rather than as text held back
    /// for its own safety. Which of the two it is, `JournalNotice` decides.
    private func failure(_ failure: JournalNotice.Failure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(failure.message)
            }
            Text(failure.consequence)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
