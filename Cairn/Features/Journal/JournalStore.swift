import AppKit
import CoreServices
import Foundation
import Observation

/// AppStorage keys for the journal, held here so no key literal is ever
/// duplicated — the same rule as `NutritionSettings`.
enum JournalSettings {
    static let folderPathKey = "journalFolderPath"
}

/// The journal's live state: which folder, what is in it, and what is being
/// typed into it right now.
///
/// The folder is the only source of truth — nothing is mirrored into SwiftData.
/// A mirror would be a second copy that diverges the first time a note is
/// written from Obsidian on the phone, which is precisely the compatibility
/// this feature is for.
@MainActor
@Observable
final class JournalStore {
    private(set) var notes: [JournalNote] = []
    private(set) var loadError: String?
    /// Set when the note being edited changed underneath. Cleared by the
    /// banner's two buttons.
    private(set) var conflict: JournalReconciliation.Outcome?
    /// The note whose last write failed, if any.
    ///
    /// While this is set the store refuses to move on to another note: the
    /// error has to stay over the text it belongs to, and that text would be
    /// unreachable the moment the buffer was replaced. A list keeping its own
    /// selection reads this so the two do not drift apart — the store having
    /// stayed on a note the sidebar has left is a worse state than either.
    private(set) var pendingWriteFailure: DateKey?
    /// Why that last write failed, in French, for the editor to show.
    ///
    /// Its own property rather than `loadError`, which it would otherwise be
    /// read from: `loadError` is cleared by any successful folder read, and the
    /// watcher re-reads the folder on every event — an iCloud sync, a note
    /// arriving, Obsidian touching its workspace file. The message would go
    /// while the failure it explains was still in force, leaving an editor that
    /// refuses to move with nothing on screen to say why. It also carries a
    /// folder that went missing and a deletion that would not go through,
    /// neither of which belongs over an open note. Set and cleared in lockstep
    /// with `pendingWriteFailure`, and only with it.
    private(set) var writeFailure: String?
    private(set) var folder: URL?

    private let defaults: UserDefaults
    /// The note being typed into, and its text. Kept apart from `notes` so the
    /// buffer survives a reload that repopulates the list.
    private var editingDate: DateKey?
    private var buffer = ""
    private var isDirty = false
    /// The file behind the note being edited as we last knew it: what was read
    /// from it when the note was opened, then whatever we wrote into it. This
    /// is what tells a change made elsewhere from a folder that has not moved
    /// under us — see `merged(_:)`.
    private var baseline: (date: DateKey, text: String)?
    private var saveTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    /// The running watcher, held as an object rather than as a raw stream so
    /// that releasing the store tears the stream down on its own — a `deinit`
    /// is never main-actor isolated, whatever class it belongs to, so this
    /// one's could not reach an isolated property to stop the stream itself.
    private var stream: FolderStream?
    /// Kept for the same reason: block-based notification observers are not
    /// zeroed out the way target/selector ones are, so they have to be removed
    /// by hand, and this object's `deinit` is where that can happen.
    private let observers = NotificationObservers()

    /// How long after the last keystroke the note is written.
    private static let saveDelay = Duration.milliseconds(700)
    /// How long a burst of file-system events is allowed to settle. iCloud
    /// drops a whole sync in one go, and re-reading the folder per file would
    /// mean dozens of passes for one arrival.
    private static let reloadDelay = Duration.milliseconds(300)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: JournalSettings.folderPathKey),
           !path.isEmpty {
            folder = URL(fileURLWithPath: path)
        }
        reload()
        startWatching()
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

    /// Points the journal at a folder, or at none.
    func choose(_ folder: URL?) {
        saveNow()
        self.folder = folder
        defaults.set(folder?.path ?? "", forKey: JournalSettings.folderPathKey)
        editingDate = nil
        buffer = ""
        isDirty = false
        baseline = nil
        conflict = nil
        pendingWriteFailure = nil
        writeFailure = nil
        reload()
        startWatching()
    }

    // MARK: - Reading

    func note(for date: DateKey) -> JournalNote? {
        notes.first { $0.date == date }
    }

    /// The buffer when that note is being edited, the file's text otherwise.
    func text(for date: DateKey) -> String {
        editingDate == date ? buffer : (note(for: date)?.text ?? "")
    }

    func reload() {
        guard let folder else {
            notes = []
            loadError = nil
            return
        }
        do {
            let fresh = try JournalFolder.notes(in: folder)
            loadError = nil
            notes = merged(fresh)
        } catch {
            // The folder was renamed, moved, or sits on a volume that is not
            // mounted. The setting is deliberately kept: losing the path
            // because a disk was asleep would be worse than an empty screen.
            loadError = "Le dossier du journal est introuvable. \(error.localizedDescription)"
            notes = []
        }
    }

    /// Reconciles what the disk now says with what is being typed.
    private func merged(_ fresh: [JournalNote]) -> [JournalNote] {
        guard let editingDate else { return fresh }
        let diskText = fresh.first { $0.date == editingDate }?.text

        guard isDirty else {
            // A note that is open and saved is the ordinary resting state, and
            // the disk is more recent than what is merely being displayed: the
            // editor takes it, as the list does, with no banner — there is no
            // unsaved work to arbitrate. Leaving the buffer alone would show
            // this morning's text over the phone's, and the next keystroke
            // would write it back over the top.
            //
            // A file that has gone leaves an empty note rather than a
            // remembered one: the day holds nothing everywhere else too.
            buffer = diskText ?? ""
            baseline = (editingDate, buffer)
            return fresh
        }

        // Nothing has happened to this note's file — the event was our own
        // save coming back, or some other note in the folder changing. Keep
        // the buffer, say nothing.
        if let baseline, baseline.date == editingDate,
           JournalReconciliation.isUnchanged(
               diskText: diskText, baselineText: baseline.text
           ) {
            return keepingBuffer(over: fresh, at: editingDate)
        }

        let outcome = JournalReconciliation.outcome(
            isDirty: true, bufferText: buffer, diskText: diskText
        )
        // Whichever way it goes, this is the file we know about from now on:
        // the banner speaks for one change made elsewhere, and must not come
        // straight back up on the next event about an unrelated note.
        baseline = (editingDate, diskText ?? "")
        switch outcome {
        case .adopt:
            // The file changed, but into exactly what is being typed here.
            // Whoever wrote it, the edit is on disk, so nothing is pending.
            isDirty = false
            conflict = nil
            // Including a write of ours that failed: the text it was holding
            // the journal for is on disk now. Nothing else would ever clear
            // this — `saveNow()` leaves on `isDirty`, which has just gone —
            // and the journal would refuse every change of note for good,
            // behind a message about text that is safely written.
            pendingWriteFailure = nil
            writeFailure = nil
            // `fresh` already holds this text, `.adopt` being the case where
            // the two agree word for word.
            return fresh
        case .conflict, .vanished:
            conflict = outcome
            return keepingBuffer(over: fresh, at: editingDate)
        }
    }

    /// The disk's notes, with what is being typed standing in for one of them:
    /// a sentence must not disappear from under the cursor. The file keeps
    /// what it has.
    private func keepingBuffer(
        over fresh: [JournalNote], at date: DateKey
    ) -> [JournalNote] {
        Self.placing(
            JournalNote(
                date: date, text: buffer,
                isReadable: fresh.first { $0.date == date }?.isReadable ?? true
            ),
            in: fresh
        )
    }

    /// `notes` with this one in it: replacing the note for that day, or slotted
    /// in where the day belongs.
    ///
    /// Nothing is re-sorted. A note's date is its identity and typing cannot
    /// change it, so the order a keystroke arrives into is the order it leaves.
    private static func placing(
        _ note: JournalNote, in notes: [JournalNote]
    ) -> [JournalNote] {
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

    // MARK: - Writing

    func update(_ text: String, for date: DateKey) {
        if editingDate != date {
            saveNow()
            // The note being left could not be written: stay on it. Replacing
            // the buffer here would leave the paragraph that failed to reach
            // the disk nowhere at all, with only a message to say so.
            guard pendingWriteFailure == nil else { return }
            // What the folder's last read says this note holds, which is what
            // its file held: the buffer only ever stands in for the note being
            // edited, and that is the one being left behind here.
            baseline = (date, note(for: date)?.text ?? "")
        }
        editingDate = date
        buffer = text
        isDirty = true
        // Shown immediately, saved in a moment: the list row's excerpt and the
        // tag list must follow the typing, not the debounce.
        notes = Self.placing(
            JournalNote(
                date: date, text: text,
                isReadable: note(for: date)?.isReadable ?? true
            ),
            in: notes
        )

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
        // A banner is a question put to the reader, and writing would answer
        // it: the buffer would go over the very file the banner is warning
        // about, while the banner stayed up offering a **Recharger** that now
        // reloads the reader's own text. Every caller comes through here — the
        // debounce, ⌘-Tab, quitting, changing note — so this is where the
        // banner is protected. `dismissConflict()` is what releases it.
        guard conflict == nil else { return }
        guard isDirty, let folder, let date = editingDate else { return }
        isDirty = false
        do {
            if JournalNote(date: date, text: buffer).isEmpty {
                // Opening today's note and typing nothing must not leave an
                // empty file in the vault. Straight out, not to the trash: it
                // never held anything.
                try JournalFolder.remove(date, in: folder, toTrash: false)
                notes.removeAll { $0.date == date }
                editingDate = nil
                baseline = (date, "")
            } else {
                try JournalFolder.write(buffer, for: date, in: folder)
                baseline = (date, buffer)
            }
            pendingWriteFailure = nil
            writeFailure = nil
            // A write that went through proves the folder is there, so a
            // message saying otherwise has had its day.
            loadError = nil
        } catch {
            isDirty = true
            pendingWriteFailure = date
            // Not `loadError`: that one belongs to the folder, and is shown
            // where the folder is chosen — a note that would not save has no
            // business appearing under « Dossier des notes » in ⌘,. The
            // editor reads `writeFailure`, which lasts exactly as long as the
            // block it explains.
            writeFailure =
                "La note n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    /// Inserts today's note in memory if it is not there, and returns its key.
    ///
    /// Nothing is written: a file appears the moment something is typed, and
    /// disappears again if the text is taken back out.
    @discardableResult
    func openToday() -> DateKey {
        let today = DateKey(Date())
        if note(for: today) == nil {
            notes = Self.placing(JournalNote(date: today, text: ""), in: notes)
        }
        return today
    }

    func delete(_ date: DateKey) {
        guard let folder else { return }
        if editingDate == date {
            saveTask?.cancel()
            editingDate = nil
            buffer = ""
            isDirty = false
            baseline = nil
            // Whatever would not write is being thrown away on purpose here.
            pendingWriteFailure = nil
            writeFailure = nil
        }
        do {
            try JournalFolder.remove(date, in: folder, toTrash: true)
            notes.removeAll { $0.date == date }
            loadError = nil
        } catch {
            loadError = "La note n'a pas pu être supprimée. \(error.localizedDescription)"
        }
    }

    // MARK: - Conflicts

    /// Drops the buffer and takes the file, dismissing the banner.
    func reloadConflicted() {
        conflict = nil
        saveTask?.cancel()
        editingDate = nil
        buffer = ""
        isDirty = false
        baseline = nil
        pendingWriteFailure = nil
        writeFailure = nil
        reload()
    }

    /// Keeps the buffer, dismisses the banner — and writes it.
    ///
    /// The writing is the point: **Garder** is the reader answering the
    /// question, and while the banner is up nothing else may write. `baseline`
    /// is already the file's text — `merged(_:)` set it when it raised the
    /// banner — so the save that follows is a change against what is on disk
    /// and not a conflict against it.
    ///
    /// Also what a change of note means, deliberately: leaving is keeping.
    /// The text typed here goes to its file, and the reader is not carrying an
    /// unanswered question onto the next note.
    func dismissConflict() {
        guard conflict != nil else { return }
        conflict = nil
        saveNow()
    }

    // MARK: - Watching

    /// Watches the folder so a note written from Obsidian — on this Mac or
    /// arriving over iCloud — shows up without anyone asking.
    ///
    /// `kFSEventStreamCreateFlagFileEvents` rather than a `DispatchSource` on
    /// the directory: a dispatch source fires when a directory *entry* changes,
    /// which misses an editor writing into an existing file in place.
    private func startWatching() {
        // Releasing the old handle stops the old stream, before a second one
        // is started on a folder that may well be the same.
        stream = nil
        guard let folder else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        // A C callback cannot capture, so the store travels through `info` as
        // an unretained pointer — unretained because the stream cannot outlive
        // the store: the handle holding it is a property of this object, and
        // is released as the object is.
        //
        // Safe to assume the main actor: the stream is scheduled on the main
        // queue two lines below, so this callback only ever runs there.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            MainActor.assumeIsolated {
                Unmanaged<JournalStore>.fromOpaque(info)
                    .takeUnretainedValue()
                    .scheduleReload()
            }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context,
            [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            // A stream that never started must not be stopped — CoreServices
            // asserts on it — so it is let go of here rather than handed to a
            // `FolderStream`. The folder simply goes unwatched: notes written
            // elsewhere then show up on the next reload rather than at once.
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = FolderStream(stream)
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reloadDelay)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

/// A started FSEvents stream, stopped and released when this object is.
///
/// The store cannot do this in its own `deinit`: a `deinit` is nonisolated
/// even on a `@MainActor` class, so it may not touch the store's isolated
/// properties. Handing the stream to an object of its own moves the teardown
/// to a `deinit` that is allowed to run it, at the very same moment — the
/// store is the only owner.
private final class FolderStream {
    private let stream: FSEventStreamRef

    init(_ stream: FSEventStreamRef) {
        self.stream = stream
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// Notification observers that unregister themselves when their owner goes.
///
/// A block-based observer is not zeroed out the way a target/selector one is:
/// the notification centre holds the block until the token is handed back. The
/// same isolation rule as `FolderStream` applies, and so does the same answer.
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
