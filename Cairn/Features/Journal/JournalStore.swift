import AppKit
import Foundation
import Observation
import SwiftData

/// AppStorage keys for the journal, held here so no key literal is ever
/// duplicated — the same rule as `NutritionSettings`.
enum JournalSettings {
    /// Where the notes used to live. Read exactly once, by
    /// `JournalImport.runIfNeeded`, and never written any more: the folder is
    /// taken in at the first launch and then forgotten.
    static let folderPathKey = "journalFolderPath"
    /// Set once `JournalImport.runIfNeeded` has run, whatever it found —
    /// explicit rather than deduced from an empty store, because a journal
    /// with no note in it is a legitimate state, not a sign recovery never
    /// happened.
    static let importDoneKey = "journalImportDone"
}

/// The journal's live state: what the base holds, and what is being typed into
/// it right now.
///
/// The base is the only source of truth. It used to be a folder shared with
/// Obsidian, and half of this file existed for that one reason: a second
/// writer meant reconciling, watching, and refusing to move on from a note
/// whose write had failed. The phone writes through the web application now,
/// so all of it has gone rather than been carried over — a `context.save()`
/// does not fail the way a read-only disk or a vanished folder did.
@MainActor
@Observable
final class JournalStore {
    /// Every day the base holds, newest first, plus the one being written in.
    ///
    /// Values rather than the `@Model` rows themselves: `JournalDay`,
    /// `JournalBook` and the list all take `JournalFileNote`, and the buffer
    /// has to be able to stand in for a note that has no row yet — today's,
    /// just opened with ⌘N.
    private(set) var notes: [JournalFileNote] = []

    /// Moves every time the store has replaced the text of the note being
    /// edited itself, rather than taken it from the editor.
    ///
    /// The editor owns the text while it holds it: it keeps it in local state
    /// and writes through to `update(_:for:)`, because a `TextEditor` handed
    /// its string again from outside loses its selection — which put the caret
    /// at the end of the note after every letter typed anywhere else. So it
    /// cannot read the store's text back continuously; it needs to be told the
    /// two moments when the store's copy is the one to show: a buffer dropped
    /// on purpose, which today means a deletion (`discardBuffer()`), and a
    /// line written into the note by something other than the editor
    /// (`append(_:for:)`).
    ///
    /// Not a change of note: `beginEditing` never moves this counter, and
    /// never has. The pane re-seeds its draft from its own
    /// `.onChange(of: day.id)` — it knows which note it is showing before this
    /// store does.
    ///
    /// A counter and not the text itself: what the editor has to know is *that*
    /// its text was replaced, and it already has `text(for:)` to read it from.
    /// Typing never moves it, which is the whole point.
    private(set) var textRevision = 0

    /// Where a note's `![](pieces-jointes/x.jpg)` resolves to.
    ///
    /// Not optional any more, and that is the point of the cache: the bytes
    /// live in the base, and `JournalAttachmentCache` materialises them under
    /// a folder that always exists. Nothing downstream — the Markdown
    /// renderer, the thumbnails, the book — has to know anything changed, and
    /// nothing has a reason to disable itself for want of a folder.
    let attachmentsBase: URL

    private let context: ModelContext
    /// The note being typed into, and its text. Kept apart from `notes` so the
    /// buffer survives a rebuild that repopulates the list.
    private var editingDate: DateKey?
    private var buffer = ""
    private var isDirty = false
    private var saveTask: Task<Void, Never>?
    /// Block-based notification observers are not zeroed out the way
    /// target/selector ones are, so they have to be removed by hand, and this
    /// object's `deinit` is where that can happen — a `deinit` is never
    /// main-actor isolated, whatever class it belongs to.
    private let observers = NotificationObservers()

    /// How long after the last keystroke the note is written.
    private static let saveDelay = Duration.milliseconds(700)

    /// - Parameter attachmentsBase: the cache directory, with no default
    ///   value on purpose. `JournalAttachmentCache.materialise` carries the
    ///   same warning for the same reason: a default of
    ///   `JournalAttachmentCache.directory` is exactly the shape every test
    ///   call takes, so a test that omitted it would write pictures into the
    ///   application's real cache folder instead of its own throwaway one.
    ///   Every caller, production and test alike, names the directory it means.
    init(container: ModelContainer, attachmentsBase: URL) {
        // The application's own context, not one of this store's making: the
        // recovery inserts its notes through `StoreMaintenance`, and a store
        // holding a context of its own would be looking at a snapshot taken
        // before any of them arrived.
        self.context = container.mainContext
        self.attachmentsBase = attachmentsBase
        refresh()
        // Anything that can take the app away has to flush the buffer first:
        // a debounce that has not fired yet is unwritten work.
        //
        // The block runs on the posting thread, which for these two is the
        // main thread — AppKit posts them from its own run loop — so assuming
        // the main actor holds. An `OperationQueue` would not do here: on
        // termination the flush has to happen before AppKit carries on, not as
        // an operation left on a run loop that is being torn down.
        for name in [
            NSApplication.willResignActiveNotification,
            NSApplication.willTerminateNotification,
        ] {
            observers.observe(name) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveNow() }
            }
        }
    }

    // MARK: - Reading

    func note(for date: DateKey) -> JournalFileNote? {
        notes.first { $0.date == date }
    }

    /// The buffer when that note is being edited, the base's text otherwise.
    func text(for date: DateKey) -> String {
        editingDate == date ? buffer : (note(for: date)?.text ?? "")
    }

    /// Rebuilds `notes` from what the base holds.
    ///
    /// Called by every write here, and by the launch once the recovery has
    /// inserted the folder's notes — that pass writes rows this store knows
    /// nothing about, and nothing else would ever tell it.
    ///
    /// The day being written in keeps its row even with no note behind it —
    /// today's just opened, or one emptied a moment ago. The pane is built
    /// from that row, and taking it away would tear down the editor the caret
    /// is sitting in.
    func refresh() {
        let rows = (try? context.fetch(FetchDescriptor<JournalNote>())) ?? []
        var fresh = rows
            .compactMap { row in
                row.dateKey.map { JournalFileNote(date: $0, text: row.text) }
            }
            .sorted { $0.date > $1.date }
        if let editingDate {
            fresh = Self.placing(
                JournalFileNote(date: editingDate, text: buffer), in: fresh
            )
        }
        notes = fresh
    }

    /// `notes` with this one in it: replacing the note for that day, or slotted
    /// in where the day belongs.
    ///
    /// Nothing is re-sorted. A note's date is its identity and typing cannot
    /// change it, so the order a keystroke arrives into is the order it leaves.
    private static func placing(
        _ note: JournalFileNote, in notes: [JournalFileNote]
    ) -> [JournalFileNote] {
        var updated = notes
        if let index = updated.firstIndex(where: { $0.date == note.date }) {
            updated[index] = note
        } else if let index = updated.firstIndex(where: { $0.date < note.date }) {
            updated.insert(note, at: index)
        } else {
            updated.append(note)
        }
        return updated
    }

    /// The row for that day, or nil.
    private func row(for date: DateKey) -> JournalNote? {
        let raw = date.raw
        var descriptor = FetchDescriptor<JournalNote>(
            predicate: #Predicate { $0.dateKeyRaw == raw }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Writing

    /// The editor has this note's text now, before a single key is pressed.
    ///
    /// Told rather than guessed: the note keeps a row even with nothing behind
    /// it, so the pane the caret is in is never torn down — today's note
    /// opened with ⌘N is exactly that note. That row is `refresh()`'s doing,
    /// which is why the list is rebuilt here rather than left as it was: the
    /// day being left may have just been emptied to nothing, and its row has
    /// to go with it now that the buffer no longer stands for it.
    ///
    /// The text comes from the base rather than from `notes`, which is the
    /// same thing one line later and says plainly where a note's text lives.
    func beginEditing(_ date: DateKey) {
        guard editingDate != date else { return }
        saveNow()
        editingDate = date
        buffer = row(for: date)?.text ?? ""
        isDirty = false
        refresh()
    }

    /// A text written by something other than the editor — a photo appended to
    /// the note, today the only case.
    ///
    /// `update(_:for:)` plus the one thing it deliberately never does: say so.
    /// The editor holds its own copy while it is being typed in, and never
    /// reads it back — that is what keeps the caret still. Which means a line
    /// added from outside is invisible to whoever is writing, until they leave
    /// the note and come back. Observed on 13 August 2026: the file was right,
    /// the list row was right, and the pane showed neither.
    ///
    /// `textRevision` is the store's way of saying "this text is mine now";
    /// the pane re-seeds its draft on it. The caret lands at the end of the
    /// note, which is where the picture went.
    func append(_ text: String, for date: DateKey) {
        update(text, for: date)
        textRevision += 1
    }

    func update(_ text: String, for date: DateKey) {
        // The note being left is written before the buffer is handed to
        // another day: a debounce that has not fired yet is unwritten work.
        // Through `beginEditing`, which is a no-op on the note already open,
        // so the one place that changes note is the one that flushes.
        beginEditing(date)
        buffer = text
        isDirty = true
        // Shown immediately, saved in a moment: the list row's excerpt and the
        // tag list must follow the typing, not the debounce.
        notes = Self.placing(JournalFileNote(date: date, text: text), in: notes)

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let date = editingDate else { return }
        isDirty = false
        if let existing = row(for: date) {
            existing.setText(buffer)
            // A note emptied to nothing goes, exactly as an emptied file used
            // to leave the vault: opening today's note and typing nothing must
            // not leave a blank day in the journal. The rule is
            // `JournalNote.isEmpty`, and it has not changed.
            //
            // The row goes; the note does not. This is a pause in the middle
            // of writing — select-all, delete, think — and `refresh()` below
            // puts the open day's row back on its own.
            if existing.isEmpty { context.delete(existing) }
        } else {
            let note = JournalNote(dateKey: date, text: buffer)
            // Never inserted at all when there is nothing to keep.
            if !note.isEmpty { context.insert(note) }
        }
        save()
        refresh()
    }

    /// Inserts today's note in memory if it is not there, and returns its key.
    ///
    /// Nothing is written: a note appears the moment something is typed, and
    /// disappears again if the text is taken back out. The day is opened for
    /// writing straight away, which is what keeps that row — ⌘N puts the caret
    /// in it, and a row that goes takes the pane with it.
    @discardableResult
    func openToday() -> DateKey {
        open(DateKey(Date()))
    }

    /// The same for any day, which is what the sidebar's calendar clicks.
    ///
    /// A day with no note gets an empty one in memory and nothing in the base
    /// — so clicking last Tuesday to write the entry one forgot costs nothing
    /// if one thinks better of it, exactly as ⌘N on today does. The row comes
    /// from `refresh()`, which keeps the open day's whether or not the base
    /// has anything for it.
    @discardableResult
    func open(_ date: DateKey) -> DateKey {
        beginEditing(date)
        return date
    }

    /// Removes the note, and only then lets go of it.
    ///
    /// That order matters: the editor must not be left open on a note the
    /// store no longer holds. `discardBuffer()` clears `editingDate`, and the
    /// pane only goes away because the row does, which is the line below.
    /// Nothing can slip in between the two — no suspension point, one actor.
    func delete(_ date: DateKey) {
        if let row = row(for: date) { context.delete(row) }
        save()
        if editingDate == date { discardBuffer() }
        notes.removeAll { $0.date == date }
    }

    /// Lets go of what is being typed without writing it.
    ///
    /// The one caller means the note is not the one being written in any more:
    /// it has just been deleted.
    private func discardBuffer() {
        saveTask?.cancel()
        saveTask = nil
        editingDate = nil
        buffer = ""
        isDirty = false
        // The editor is showing that buffer: it has to be told to take the
        // store's text again rather than keep the one it was given.
        textRevision += 1
    }

    /// Writes, and says nothing when it cannot.
    ///
    /// There is no message to show and no state to hold back: a
    /// `context.save()` does not fail the way writing to a folder someone had
    /// unmounted did, which is the whole reason `writeFailure` and its refusal
    /// to change note went with the folder. What is left is a store that is
    /// broken outright, and the next launch has nothing better to offer.
    private func save() {
        try? context.save()
    }

    // MARK: - Pièces jointes

    /// Takes pictures into the journal and writes their links at the end of
    /// the note.
    ///
    /// - Returns: the names refused, for the caller to say out loud. A file
    ///   ignored in silence is a file one believes was added.
    @discardableResult
    func addAttachments(from urls: [URL], to date: DateKey) -> [String] {
        var links: [String] = []
        var refused: [String] = []
        for url in urls {
            guard JournalAttachmentRules.allowedExtensions
                .contains(url.pathExtension.lowercased())
            else {
                refused.append(url.lastPathComponent)
                continue
            }
            // Reduced on the way in when it is worth it — see
            // `JournalAttachmentRules.maxPixels`. A picture already small
            // enough is taken byte for byte: re-encoding it would only lose
            // detail. Reduced from the URL rather than from its bytes, so a
            // photograph is never fully decoded to be shrunk.
            let reduced = JournalFolder.reduced(at: url)
            guard let data = reduced ?? (try? Data(contentsOf: url)),
                  let link = attach(
                      data, extension: reduced == nil
                          ? url.pathExtension.lowercased() : "jpg",
                      to: date
                  )
            else {
                refused.append(url.lastPathComponent)
                continue
            }
            links.append(link)
        }
        appendLinks(links, to: date)
        return refused
    }

    /// The same from bytes, for what a paste hands over: the clipboard carries
    /// an image far more often than it carries a file.
    ///
    /// Kept as PNG unless it had to be reduced — a screenshot is what a paste
    /// usually is, and re-encoding one to JPEG would blur the very text it was
    /// taken for.
    @discardableResult
    func addAttachment(_ data: Data, to date: DateKey) -> Bool {
        let reduced = JournalFolder.reduced(data)
        guard let link = attach(
            reduced ?? data, extension: reduced == nil ? "png" : "jpg", to: date
        ) else { return false }
        appendLinks([link], to: date)
        return true
    }

    /// One picture into the base and into the cache, and the Markdown line
    /// that points at it.
    ///
    /// The name is the key, and it is unique across the whole journal — which
    /// is why the taken set is every attachment the base holds rather than the
    /// day's. Materialised straight away so the thumbnail the list is about to
    /// draw has a file to read.
    private func attach(
        _ data: Data, extension ext: String, to date: DateKey
    ) -> String? {
        let taken = Set(
            ((try? context.fetch(FetchDescriptor<JournalAttachment>())) ?? [])
                .map(\.fileName)
        )
        let attachment = JournalAttachment(
            fileName: JournalAttachmentRules.fileName(
                for: date, extension: ext, taken: taken
            ),
            data: data
        )
        context.insert(attachment)
        save()
        // A cache that could not be written loses nothing — it is derived, and
        // rebuilt at the next launch — so the picture still counts as added.
        // The explicit `_ =`: `@discardableResult` does not cover the second
        // `Optional` that `try?` wraps the returned URL in, exactly as
        // `CairnApp.init` notes about `StoreMaintenance.run`.
        _ = try? JournalAttachmentCache.materialise(
            attachment, directory: attachmentsBase
        )
        return JournalAttachmentRules.link(to: attachment.fileName)
    }

    /// The links at the end of the note, through the store.
    ///
    /// `open` first: a day listed only because an outing wrote something has
    /// no note yet, and writing into it has to create one. `append` rather
    /// than `update`, so the editor is told the text is the store's again.
    private func appendLinks(_ links: [String], to date: DateKey) {
        guard !links.isEmpty else { return }
        open(date)
        append(
            JournalAttachmentRules.appending(links, to: text(for: date)),
            for: date
        )
    }
}

/// Notification observers that unregister themselves when their owner goes.
///
/// A block-based observer is not zeroed out the way a target/selector one is:
/// the notification centre holds the block until the token is handed back. A
/// `deinit` is nonisolated even on a `@MainActor` class, so it may not touch
/// the store's isolated properties — handing the tokens to an object of their
/// own moves the teardown to a `deinit` that is allowed to run it, at the very
/// same moment, the store being the only owner.
private final class NotificationObservers {
    private var tokens: [any NSObjectProtocol] = []

    func observe(
        _ name: Notification.Name,
        using block: @escaping @Sendable (Notification) -> Void
    ) {
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: nil, using: block
            )
        )
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
