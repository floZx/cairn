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

    /// What the file actually holds, which is the only thing a test about
    /// losing someone else's sentence can believe.
    private func fileText(_ date: DateKey, in folder: URL) throws -> String {
        try String(
            contentsOf: JournalFolder.url(for: date, in: folder), encoding: .utf8
        )
    }

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

    /// The banner asks a question; nothing but the answer may settle it.
    ///
    /// A banner can only go up while something is unsaved, which is to say
    /// while a save is already pending: the debounce firing 600 ms later, a ⌘-Tab
    /// away from the window, or a click on another note would otherwise write
    /// the buffer over the very file the banner is warning about — and leave
    /// the banner up, still offering a **Recharger** that now reloads the
    /// reader's own text over the sentence written on the phone.
    @Test("le bandeau de conflit suspend l'enregistrement du tampon")
    func aConflictHoldsTheSaveBack() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("ma phrase", for: day)
        store.saveNow()
        store.update("ma phrase, et la suite", for: day)
        try JournalFolder.write("celle du téléphone", for: day, in: folder)
        store.reload()
        #expect(store.conflict == .conflict)

        // The debounce fires, the window loses focus, the app is quit: all
        // three come here, and none of them may answer for the reader.
        store.saveNow()
        #expect(try fileText(day, in: folder) == "celle du téléphone")
        #expect(store.conflict == .conflict)
        #expect(store.text(for: day) == "ma phrase, et la suite")
    }

    @Test("« Garder » écrit le tampon et retire le bandeau")
    func keepingWritesTheBuffer() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("ma phrase", for: day)
        store.saveNow()
        store.update("ma phrase, et la suite", for: day)
        try JournalFolder.write("celle du téléphone", for: day, in: folder)
        store.reload()
        #expect(store.conflict == .conflict)

        store.dismissConflict()
        #expect(store.conflict == nil)
        #expect(try fileText(day, in: folder) == "ma phrase, et la suite")
    }

    /// A write that failed, then someone else putting exactly that text on
    /// disk. The edit is saved — by another hand, but saved — so the journal
    /// has nothing left to hold on to.
    @Test("une adoption externe purge l'échec d'écriture")
    func anAdoptionPurgesTheWriteFailure() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("à sauver", for: day)
        try FileManager.default.removeItem(at: folder)
        store.saveNow()
        #expect(store.pendingWriteFailure == day)

        // The folder comes back with the phone's copy of the same paragraph.
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        try JournalFolder.write("à sauver", for: day, in: folder)
        store.reload()
        #expect(store.pendingWriteFailure == nil)
        #expect(store.writeFailure == nil)

        // Which is what lets the journal move on: nothing else ever clears
        // that flag, `saveNow()` having nothing left to write.
        store.update("une autre note", for: otherDay)
        #expect(store.text(for: otherDay) == "une autre note")
    }

    /// The three ways of letting go of a note on purpose. Each clears the
    /// buffer; each has to clear the message that belonged to it, or the
    /// journal stays frozen over a note nobody is on any more.
    @Test("changer de dossier purge l'échec d'écriture")
    func choosingAnotherFolderPurgesTheWriteFailure() throws {
        let folder = try makeFolder()
        let other = try makeFolder()
        defer { discard(folder); discard(other) }
        let store = makeStore(in: folder)

        store.update("à sauver", for: day)
        try FileManager.default.removeItem(at: folder)
        store.saveNow()
        #expect(store.writeFailure != nil)

        store.choose(other)
        #expect(store.pendingWriteFailure == nil)
        #expect(store.writeFailure == nil)
    }

    @Test("supprimer la note purge l'échec d'écriture")
    func deletingTheNotePurgesTheWriteFailure() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("à sauver", for: day)
        try FileManager.default.removeItem(at: folder)
        store.saveNow()
        #expect(store.writeFailure != nil)

        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        store.delete(day)
        #expect(store.pendingWriteFailure == nil)
        #expect(store.writeFailure == nil)
    }

    @Test("recharger depuis le disque purge l'échec d'écriture")
    func reloadingFromDiskPurgesTheWriteFailure() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("à sauver", for: day)
        try FileManager.default.removeItem(at: folder)
        store.saveNow()
        #expect(store.writeFailure != nil)

        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        store.reloadConflicted()
        #expect(store.pendingWriteFailure == nil)
        #expect(store.writeFailure == nil)
    }

    /// **Recharger** does not close the editor: the pane is not rebuilt, the
    /// caret stays where it is. So the store has to go on knowing that the
    /// note is held, or the next change arriving from the phone lands in
    /// `notes` without a word to the editor — which then writes its own copy
    /// of a text nobody has seen since, over the file, with no banner.
    ///
    /// The editor's rule is played out here in three lines, because the whole
    /// point is what the *view* does with what the store says: it takes the
    /// store's text when `textRevision` moves, and never otherwise.
    @Test("après Recharger, la note reste tenue par l'éditeur")
    func afterReloadingTheNoteIsStillHeld() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        var editorText = ""
        var seenRevision = -1
        func editorFollows() {
            guard store.textRevision != seenRevision else { return }
            seenRevision = store.textRevision
            editorText = store.text(for: day)
        }

        store.update("ma phrase", for: day)
        store.saveNow()
        editorFollows()
        store.update("ma phrase, et la suite", for: day)
        editorText = "ma phrase, et la suite"
        try JournalFolder.write("celle du téléphone", for: day, in: folder)
        store.reload()
        #expect(store.conflict == .conflict)

        // The reader takes the file. The editor is still on this note.
        store.reloadConflicted()
        editorFollows()
        #expect(editorText == "celle du téléphone")

        // The rest of the sync arrives — an iCloud burst delivers a vault in
        // several goes — and has to reach the editor.
        try JournalFolder.write("celle du téléphone, suite", for: day, in: folder)
        store.reload()
        editorFollows()
        #expect(editorText == "celle du téléphone, suite")

        // One letter typed into it: what the editor sends is what the editor
        // holds, and nothing typed can rescue a text it was never shown.
        store.update(editorText + " et moi", for: day)
        store.saveNow()
        let onDisk = try fileText(day, in: folder)
        #expect(onDisk.contains("suite"))
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

    /// The file goes; the note being written in stays.
    ///
    /// Select-all, delete, then a pause to think about the next sentence: the
    /// file must not be left empty in the vault, and the row under the caret
    /// must not go with it — the pane showing it would be torn down mid-edit.
    @Test("une note réduite à des blancs quitte le dossier, pas la liste")
    func aNoteEmptiedToWhitespaceLeavesTheFolderButNotTheList() throws {
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
        #expect(store.note(for: day) != nil)

        // And it survives the watcher noticing the file we just removed.
        store.reload()
        #expect(store.note(for: day) != nil)
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

    /// The signal the editor waits on to take the store's text again.
    ///
    /// It must not move under the typing: the editor holds its own copy
    /// precisely so that a `TextEditor` is never handed its string back from
    /// outside, which is what threw the caret to the end of the note after
    /// every letter typed in the middle of a sentence. Our own save coming
    /// back through the watcher is the case that would have moved it.
    @Test("taper ne fait pas avancer la révision du texte")
    func typingNeverMovesTheTextRevision() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)
        let start = store.textRevision

        store.update("un", for: day)
        store.update("un, deux", for: day)
        store.saveNow()
        store.reload()
        store.update("un, deux, trois", for: day)

        #expect(store.textRevision == start)
    }

    /// A note open in the editor, nothing typed into it, and the phone's
    /// version lands. The buffer takes it — there is nothing to arbitrate —
    /// and the editor has to be told, or it would keep the old text on screen
    /// and write it back over the new one at the next keystroke.
    @Test("le texte arrivé du téléphone fait avancer la révision")
    func anAdoptedDiskTextMovesTheTextRevision() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        try JournalFolder.write("du matin", for: day, in: folder)
        let store = makeStore(in: folder)

        store.beginEditing(day)
        #expect(store.text(for: day) == "du matin")
        let opened = store.textRevision

        try JournalFolder.write("écrit sur le téléphone", for: day, in: folder)
        store.reload()
        #expect(store.text(for: day) == "écrit sur le téléphone")
        #expect(store.textRevision == opened + 1)

        // And an event about a folder that has not moved since leaves it be:
        // an iCloud sync must not walk the caret to the end of the note.
        store.reload()
        #expect(store.textRevision == opened + 1)
    }

    /// A keystroke the store turns down has to be taken back off the screen.
    ///
    /// While another note's write is pending, `update(_:for:)` refuses every
    /// change: the text that would not reach the disk has to stay where the
    /// message about it is. The editor holds its own copy now, so without a
    /// word from the store it would go on showing letters this store has never
    /// had — and drop them silently at the next change of note, having just
    /// told the reader, in the notice above, that they are not being kept.
    @Test("une frappe refusée est reprise à l'éditeur")
    func arefusedKeystrokeIsTakenBack() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("à sauver", for: day)
        try FileManager.default.removeItem(at: folder)
        store.saveNow()
        #expect(store.pendingWriteFailure == day)
        let held = store.textRevision

        store.update("une autre note", for: otherDay)
        #expect(store.text(for: otherDay) == "")
        #expect(store.textRevision > held)
    }

    /// The one case where the text on screen is deliberately *not* the file's:
    /// the banner keeps the typing, so the editor must not be re-seeded.
    @Test("un conflit ne fait pas avancer la révision du texte")
    func aConflictNeverMovesTheTextRevision() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("ma phrase", for: day)
        store.saveNow()
        store.update("ma phrase, et la suite", for: day)
        let typed = store.textRevision

        try JournalFolder.write("celle du téléphone", for: day, in: folder)
        store.reload()
        #expect(store.conflict == .conflict)
        #expect(store.textRevision == typed)
    }

    @Test("recharger depuis le disque fait avancer la révision")
    func reloadingFromDiskMovesTheTextRevision() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        store.update("ma phrase", for: day)
        store.saveNow()
        store.update("ma phrase, et la suite", for: day)
        try JournalFolder.write("celle du téléphone", for: day, in: folder)
        store.reload()
        let typed = store.textRevision

        store.reloadConflicted()
        #expect(store.text(for: day) == "celle du téléphone")
        #expect(store.textRevision > typed)
    }

    /// ⌘N puts today's note in the list without writing a file. The folder is
    /// watched, and an iCloud vault delivers events for its own reasons: a
    /// re-read must not take back the note the caret was just placed in.
    @Test("la note du jour ouverte survit à une relecture du dossier")
    func todaysOpenNoteSurvivesAReload() throws {
        let folder = try makeFolder()
        defer { discard(folder) }
        let store = makeStore(in: folder)

        let today = store.openToday()
        store.reload()

        #expect(store.note(for: today) != nil)
    }
}
