import Testing
import Foundation
import SwiftData
@testable import Cairn

/// The store's own wiring, driven without a clock: `saveNow()` is called where
/// the debounce would call it, so nothing here waits on a timer.
///
/// The mounting is what is left of it once the folder has gone: an in-memory
/// container, and a throwaway directory for the attachment cache. No journal
/// folder, no `UserDefaults` suite — the store reads neither any more.
@MainActor
@Suite("JournalStore")
struct JournalStoreTests {
    /// A throwaway attachment cache, discarded by the caller.
    ///
    /// Never `JournalAttachmentCache.vaultRoot`, which names the
    /// application's real cache folder — the same rule
    /// `Tests/JournalAttachmentCacheTests.swift` states at length, and the
    /// reason `JournalStore.init` takes this directory rather than defaulting
    /// to it.
    private func makeCache() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    private func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private let day = DateKey(raw: "2026-08-01")!
    private let otherDay = DateKey(raw: "2026-07-31")!

    /// What the base actually holds, which is the only thing a test about a
    /// note reaching the store can believe.
    private func rows(_ container: ModelContainer) throws -> [JournalNote] {
        try ModelContext(container)
            .fetch(FetchDescriptor<JournalNote>())
            .sorted { $0.dateKeyRaw > $1.dateKeyRaw }
    }

    @Test("un texte écrit se relit dans la base")
    func atextWrittenIsReadBackFromTheStore() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("Promenade avec #Sam.", for: day)
        store.saveNow()

        #expect(store.text(for: day) == "Promenade avec #Sam.")
        let rows = try rows(container)
        #expect(rows.count == 1)
        #expect(rows[0].text == "Promenade avec #Sam.")
        // The tags follow the text, since `setText` is what wrote it.
        #expect(rows[0].tags == Set([JournalTag(name: "Sam")!]))
    }

    /// The list follows the typing, not the debounce: the row's excerpt and
    /// its chips are drawn from `notes`, which must not wait 700 ms.
    @Test("la liste suit la frappe, sans attendre l'enregistrement")
    func thelistFollowsTheTypingRatherThanTheSave() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("du texte", for: day)

        #expect(store.note(for: day)?.text == "du texte")
        #expect(try rows(container).isEmpty)
    }

    /// A second store on the same container reads what the first one wrote:
    /// the text is in the base, not in a buffer somebody happens to hold.
    @Test("un second magasin sur la même base relit la note")
    func asecondStoreOnTheSameContainerReadsTheNote() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("écrit ici", for: day)
        store.saveNow()

        let reopened = JournalStore(container: container, attachmentsBase: cache)
        #expect(reopened.text(for: day) == "écrit ici")
        #expect(reopened.notes.map(\.date) == [day])
    }

    /// The row goes; the note being written in stays.
    ///
    /// Select-all, delete, then a pause to think about the next sentence: the
    /// base must not keep an empty note, and the row under the caret must not
    /// go with it — the pane showing it would be torn down mid-edit. The rule
    /// is `JournalNote.isEmpty`, unchanged from the day it was a file.
    @Test("une note réduite à des blancs quitte la base, pas la liste")
    func anoteEmptiedToWhitespaceLeavesTheStoreButNotTheList() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("du texte", for: day)
        store.saveNow()
        #expect(try rows(container).count == 1)

        store.update("  \n  ", for: day)
        store.saveNow()
        #expect(try rows(container).isEmpty)
        #expect(store.note(for: day) != nil)

        // And it survives the list being rebuilt from the base.
        store.refresh()
        #expect(store.note(for: day) != nil)
    }

    @Test("la note du jour seule n'écrit rien")
    func openingTodayWritesNothing() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        let today = store.openToday()
        store.saveNow()

        #expect(store.note(for: today) != nil)
        #expect(try rows(container).isEmpty)
    }

    /// ⌘N puts today's note in the list without writing a row. A list rebuilt
    /// from the base must not take back the note the caret was just placed in.
    @Test("la note du jour ouverte survit à une relecture de la base")
    func todaysOpenNoteSurvivesARefresh() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        let today = store.openToday()
        store.refresh()

        #expect(store.note(for: today) != nil)
    }

    /// Leaving a note writes it: the debounce may not have fired, and the
    /// text typed into the note being left is not the next note's business.
    @Test("changer de note enregistre celle qu'on quitte")
    func leavingAnoteWritesIt() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("le premier jour", for: day)
        store.update("le second jour", for: otherDay)

        #expect(try rows(container).map(\.text) == ["le premier jour"])
        #expect(store.text(for: day) == "le premier jour")
        #expect(store.text(for: otherDay) == "le second jour")

        store.saveNow()
        #expect(try rows(container).map(\.text) == ["le premier jour", "le second jour"])
    }

    @Test("ouvrir une note donne le texte que la base tient")
    func openinganoteHandsBackTheStoresText() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(JournalNote(dateKey: day, text: "du matin"))
        try context.save()

        let store = JournalStore(container: container, attachmentsBase: cache)
        store.beginEditing(day)
        #expect(store.text(for: day) == "du matin")
    }

    @Test("supprimer une note la retire de la base et de la liste")
    func deletinganoteRemovesItEverywhere() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("à supprimer", for: day)
        store.saveNow()

        store.delete(day)
        #expect(store.note(for: day) == nil)
        #expect(try rows(container).isEmpty)

        // And nothing left over writes it back: the buffer went with the note.
        store.saveNow()
        #expect(try rows(container).isEmpty)
    }

    // MARK: - La révision du texte

    /// The signal the editor waits on to take the store's text again.
    ///
    /// It must not move under the typing: the editor holds its own copy
    /// precisely so that a `TextEditor` is never handed its string back from
    /// outside, which is what threw the caret to the end of the note after
    /// every letter typed in the middle of a sentence.
    @Test("taper ne fait pas avancer la révision du texte")
    func typingNeverMovesTheTextRevision() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)
        let start = store.textRevision

        store.update("un", for: day)
        store.update("un, deux", for: day)
        store.saveNow()
        store.refresh()
        store.update("un, deux, trois", for: day)

        #expect(store.textRevision == start)
    }

    /// A deletion is one of the two moments the store's copy wins: the text
    /// the editor was holding is not there any more.
    @Test("supprimer la note fait avancer la révision du texte")
    func deletingTheNoteMovesTheTextRevision() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("à supprimer", for: day)
        store.saveNow()
        let typed = store.textRevision

        store.delete(day)
        #expect(store.textRevision > typed)
        #expect(store.text(for: day) == "")
    }

    /// A line added from outside the editor — a photo, today the only case —
    /// is invisible to whoever is writing until the store says the text is
    /// its own again.
    @Test("un texte ajouté hors de l'éditeur fait avancer la révision")
    func atextAppendedFromOutsideMovesTheTextRevision() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.update("ma phrase", for: day)
        let typed = store.textRevision

        store.append("ma phrase\n\n![](pieces-jointes/x.jpg)", for: day)
        #expect(store.textRevision > typed)
        #expect(store.text(for: day).hasSuffix("![](pieces-jointes/x.jpg)"))
    }

    // MARK: - Les pièces jointes

    @Test("une photo déposée entre en base, dans le cache, et dans la note")
    func adroppedPictureEntersTheStoreTheCacheAndTheNote() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)
        let source = cache.appending(path: "IMG_4032.JPG")
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xDB])
        try bytes.write(to: source)

        #expect(store.addAttachments(from: [source], to: day).isEmpty)

        let attachments = try ModelContext(container)
            .fetch(FetchDescriptor<JournalAttachment>())
        #expect(attachments.count == 1)
        // The name is the journal's own, not the camera's: two "IMG_4032.jpg"
        // would eventually meet.
        #expect(attachments[0].fileName == "2026-08-01-1.jpg")
        // The bytes are the ones dropped: a picture already under the ceiling
        // is taken untouched.
        #expect(attachments[0].data == bytes)
        // Materialised where the note's own link points, which is the whole
        // point: this is `attachmentsBase.appending(path: linkPath)`, the exact
        // resolution `MarkdownText`, `JournalThumbnails` and the PDF book do.
        // A flat cache made every one of those links miss in silence.
        #expect(store.text(for: day) == "![](pieces-jointes/2026-08-01-1.jpg)")
        #expect(
            try Data(contentsOf: cache.appending(path: "pieces-jointes/2026-08-01-1.jpg"))
                == bytes
        )
        // The original stays where it was: a journal that swallowed originals
        // is a journal one stops dropping things on.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("deux photos du même jour ne se marchent pas dessus")
    func twoPicturesOfTheSameDayCoexist() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)

        store.addAttachment(Data([0x89, 0x50]), to: day)
        store.addAttachment(Data([0x89, 0x51]), to: day)

        let names = try ModelContext(container)
            .fetch(FetchDescriptor<JournalAttachment>())
            .map(\.fileName)
            .sorted()
        #expect(names == ["2026-08-01-1.png", "2026-08-01-2.png"])
        #expect(
            store.text(for: day)
                == """
                ![](pieces-jointes/2026-08-01-1.png)

                ![](pieces-jointes/2026-08-01-2.png)
                """
        )
    }

    /// Refused out loud rather than in silence: a file one believes was added
    /// is worse than one that says why it was not.
    @Test("un fichier qui n'est pas une image est refusé par son nom")
    func afileThatIsNotAPictureIsRefusedByName() throws {
        let cache = try makeCache()
        defer { discard(cache) }
        let container = try AppModelContainer.inMemory()
        let store = JournalStore(container: container, attachmentsBase: cache)
        let source = cache.appending(path: "notes.txt")
        try Data("x".utf8).write(to: source)

        #expect(store.addAttachments(from: [source], to: day) == ["notes.txt"])
        #expect(store.text(for: day) == "")
        #expect(
            try ModelContext(container)
                .fetch(FetchDescriptor<JournalAttachment>())
                .isEmpty
        )
    }
}
