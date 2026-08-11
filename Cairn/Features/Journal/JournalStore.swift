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
        guard let editingDate, isDirty else { return fresh }
        let diskText = fresh.first { $0.date == editingDate }?.text

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
        var kept = fresh.filter { $0.date != date }
        kept.append(JournalNote(date: date, text: buffer))
        return kept.sorted { $0.date > $1.date }
    }

    // MARK: - Writing

    func update(_ text: String, for date: DateKey) {
        if editingDate != date {
            saveNow()
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
        var updated = notes.filter { $0.date != date }
        updated.append(JournalNote(date: date, text: text))
        notes = updated.sorted { $0.date > $1.date }

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
        guard isDirty, let folder, let date = editingDate else { return }
        isDirty = false
        do {
            if buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            loadError = nil
        } catch {
            isDirty = true
            loadError = "La note n'a pas pu être enregistrée. \(error.localizedDescription)"
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
            notes.insert(JournalNote(date: today, text: ""), at: 0)
            notes.sort { $0.date > $1.date }
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
        reload()
    }

    /// Keeps the buffer and dismisses the banner.
    func dismissConflict() {
        conflict = nil
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
        FSEventStreamStart(stream)
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
