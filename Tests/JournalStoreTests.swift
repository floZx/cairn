import Testing
import Foundation
@testable import Cairn

/// The store's own wiring, driven without a clock: `saveNow()` and `reload()`
/// are called where the debounce and the folder watcher would call them, so
/// nothing here waits on a timer or on an FSEvents delivery.
@MainActor
@Suite("JournalStore")
struct JournalStoreTests {
    /// A throwaway directory, discarded by the caller.
    private func makeFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    /// A store on that folder, with defaults of its own — never `.standard`,
    /// which belongs to whatever app is running the tests.
    private func makeStore(in folder: URL) -> JournalStore {
        let store = JournalStore(
            defaults: UserDefaults(suiteName: defaultsSuite(for: folder))!
        )
        store.choose(folder)
        return store
    }

    private func defaultsSuite(for folder: URL) -> String {
        "CairnTests.\(folder.lastPathComponent)"
    }

    /// Removes the folder and the defaults that went with it.
    private func discard(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: defaultsSuite(for: folder))
    }

    private let day = DateKey(raw: "2026-08-01")!
    private let otherDay = DateKey(raw: "2026-07-31")!

    @Test("notre propre écriture qui revient ne lève pas de conflit")
    func ourOwnWriteComingBackIsSilent() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("un", for: day)
        store.saveNow()
        // The pause was long enough to save, and the sentence went on
        // afterwards — which is when the watcher delivers our own write.
        store.update("un, deux", for: day)
        store.reload()

        #expect(store.conflict == nil)
        #expect(store.text(for: day) == "un, deux")
    }

    @Test("une réécriture ailleurs lève un conflit, et une seule fois")
    func anOutsideRewriteRaisesOneConflict() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("ma phrase", for: day)
        store.saveNow()
        store.update("ma phrase, et la suite", for: day)
        try JournalFolder.write("celle du téléphone", for: day, in: folder)
        store.reload()

        #expect(store.conflict == .conflict)
        // What is being typed stays under the cursor; the file keeps its own.
        #expect(store.text(for: day) == "ma phrase, et la suite")

        // Dismissed, then another event about a folder that has not moved
        // again: the banner must not come straight back up.
        store.dismissConflict()
        store.reload()
        #expect(store.conflict == nil)
        #expect(store.text(for: day) == "ma phrase, et la suite")
    }

    @Test("une note enregistrée et ouverte suit le disque, sans bandeau")
    func anOpenSavedNoteFollowsTheDisk() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("écrit ici", for: day)
        store.saveNow()
        // Nothing is unsaved, so nothing is at stake: the phone's sentence is
        // the more recent one and the editor takes it, as the list does.
        try JournalFolder.write("écrit sur le téléphone", for: day, in: folder)
        store.reload()

        #expect(store.text(for: day) == "écrit sur le téléphone")
        #expect(store.conflict == nil)

        // And the file we know about followed, so typing on top of what was
        // just adopted is not a conflict against a change already taken.
        store.update("écrit sur le téléphone, puis ici", for: day)
        store.reload()
        #expect(store.conflict == nil)
        #expect(store.text(for: day) == "écrit sur le téléphone, puis ici")
    }

    @Test("un enregistrement en échec retient la note ouverte")
    func aFailedWriteHoldsTheNoteOpen() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("à sauver", for: day)
        // The folder goes away under it — a volume unmounted, a vault moved.
        try FileManager.default.removeItem(at: folder)
        store.saveNow()
        #expect(store.pendingWriteFailure == day)

        store.update("une autre note", for: otherDay)
        #expect(store.pendingWriteFailure == day)
        #expect(store.text(for: day) == "à sauver")
        #expect(store.text(for: otherDay) == "")

        // Written at last: the note is let go of and one can move on.
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        store.saveNow()
        #expect(store.pendingWriteFailure == nil)
        store.update("une autre note", for: otherDay)
        #expect(store.text(for: otherDay) == "une autre note")
        #expect(store.text(for: day) == "à sauver")
    }

    /// The message has to last exactly as long as the block it explains.
    ///
    /// `loadError` cannot carry it: any successful folder read clears that one,
    /// and the watcher re-reads the folder on every event — an iCloud sync, a
    /// note arriving, another app touching a file. The editor would go quiet
    /// while still refusing to move.
    @Test("le message d'échec survit à une relecture du dossier")
    func aFailureMessageOutlivesAReload() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("à sauver", for: day)
        try FileManager.default.removeItem(at: folder)
        store.saveNow()
        #expect(store.writeFailure != nil)

        // The folder comes back — a volume remounted — and the watcher fires.
        // Nothing has been saved yet: the note is still held.
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        store.reload()
        #expect(store.loadError == nil)
        #expect(store.pendingWriteFailure == day)
        #expect(store.writeFailure != nil)

        // Written at last, and only then does the message go.
        store.saveNow()
        #expect(store.pendingWriteFailure == nil)
        #expect(store.writeFailure == nil)
    }

    @Test("une note réduite à des blancs quitte le dossier")
    func aNoteEmptiedToWhitespaceLeavesTheFolder() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)
        let file = JournalFolder.url(for: day, in: folder)

        store.update("du texte", for: day)
        store.saveNow()
        #expect(FileManager.default.fileExists(atPath: file.path))

        store.update("  \n  ", for: day)
        store.saveNow()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.note(for: day) == nil)
    }

    @Test("la note du jour seule n'écrit rien")
    func openingTodayWritesNothing() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        let today = store.openToday()
        store.saveNow()

        #expect(store.note(for: today) != nil)
        #expect(try JournalFolder.notes(in: folder).isEmpty)
    }
}
