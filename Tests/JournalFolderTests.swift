import Testing
import AppKit
import Foundation
@testable import Cairn

/// The reading half, which is all that is left: naming the files, listing a
/// folder of them, and bringing a picture down to size. Nothing here writes a
/// note any more — that went with the folder, and what remains serves the
/// recovery.
@Suite("JournalFolder")
struct JournalFolderTests {
    /// A throwaway directory, removed by the caller.
    private func makeFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    /// A note file, laid down by hand.
    ///
    /// `JournalFolder.write` used to do this and no longer exists: Cairn does
    /// not write into a journal folder any more. What these tests need is a
    /// folder that already holds notes — the state a first launch finds — so
    /// the fixture writes the bytes itself.
    private func write(_ text: String, for date: DateKey, in folder: URL) throws {
        try Data(text.utf8).write(
            to: folder.appending(path: JournalFolder.fileName(for: date))
        )
    }

    @Test("le nom de fichier est la date suivie de .md")
    func fileNaming() {
        #expect(JournalFolder.fileName(for: DateKey(raw: "2026-08-11")!) == "2026-08-11.md")
    }

    @Test("seuls les noms de date donnent une note")
    func fileNameParsing() {
        #expect(JournalFolder.date(fromFileName: "2026-08-11.md")?.raw == "2026-08-11")
        #expect(JournalFolder.date(fromFileName: "notes.md") == nil)
        #expect(JournalFolder.date(fromFileName: "2026-13-01.md") == nil)
        #expect(JournalFolder.date(fromFileName: "2026-08-11.txt") == nil)
        #expect(JournalFolder.date(fromFileName: "2026-08-11") == nil)
    }

    @Test("une note du dossier est lue avec ses étiquettes")
    func anoteIsReadWithItsTags() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try write("Promenade avec #Sam.", for: DateKey(raw: "2026-08-11")!, in: folder)
        let notes = try JournalFolder.notes(in: folder)
        #expect(notes.count == 1)
        #expect(notes[0].date.raw == "2026-08-11")
        #expect(notes[0].text == "Promenade avec #Sam.")
        #expect(notes[0].tags == Set([JournalTag(name: "Sam")!]))
    }

    @Test("ce qui n'est pas une note du jour est ignoré")
    func nonDailyFilesAreIgnored() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try "x".write(
            to: folder.appending(path: "notes.md"), atomically: true, encoding: .utf8
        )
        try "x".write(
            to: folder.appending(path: "2026-13-01.md"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: folder.appending(path: "sous-dossier"), withIntermediateDirectories: true
        )
        try "x".write(
            to: folder.appending(path: "sous-dossier/2026-08-11.md"),
            atomically: true, encoding: .utf8
        )
        try write("bon", for: DateKey(raw: "2026-08-11")!, in: folder)

        let notes = try JournalFolder.notes(in: folder)
        #expect(notes.map(\.date.raw) == ["2026-08-11"])
        #expect(notes[0].text == "bon")
    }

    @Test("les notes sortent de la plus récente à la plus ancienne")
    func notesAreSortedNewestFirst() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        for raw in ["2026-08-09", "2026-08-11", "2026-08-10"] {
            try write(raw, for: DateKey(raw: raw)!, in: folder)
        }
        #expect(
            try JournalFolder.notes(in: folder).map(\.date.raw)
                == ["2026-08-11", "2026-08-10", "2026-08-09"]
        )
    }

    @Test("un fichier illisible est listé plutôt qu'omis")
    func undecodableFileIsStillListed() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // 0xFF 0xFE 0xFF 0xFE is not valid UTF-8, so decoding fails and the
        // note is listed with isReadable: false instead — there is no
        // fallback encoding. `JournalImport` reads that flag and rereads the
        // raw bytes rather than letting a damaged file become a blank note.
        try Data([0xFF, 0xFE, 0xFF, 0xFE]).write(
            to: folder.appending(path: "2026-08-11.md")
        )
        let notes = try JournalFolder.notes(in: folder)
        #expect(notes.count == 1)
        #expect(!notes[0].isReadable)
        #expect(notes[0].summary == "contenu illisible")
    }

    @Test("un espace réservé iCloud non téléchargé n'est pas listé")
    func iCloudPlaceholderIsNotListed() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try write("réelle", for: DateKey(raw: "2026-08-10")!, in: folder)
        try Data().write(to: folder.appending(path: ".2026-08-11.md.icloud"))

        let notes = try JournalFolder.notes(in: folder)
        #expect(notes.map(\.date.raw) == ["2026-08-10"])
    }

    @Test("un fichier .icloud nu ne fait pas planter le listing")
    func bareICloudFileDoesNotCrash() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try Data().write(to: folder.appending(path: ".icloud"))
        #expect(try JournalFolder.notes(in: folder).isEmpty)
    }

    @Test("un espace réservé pour un fichier qui n'est pas une note est ignoré")
    func iCloudPlaceholderForNonNoteIsIgnored() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try Data().write(to: folder.appending(path: ".notes.md.icloud"))
        #expect(try JournalFolder.notes(in: folder).isEmpty)
    }

    @Test("le dossier des pièces jointes porte le nom que les liens citent")
    func theattachmentsFolderIsTheOneTheLinksName() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(
            JournalFolder.attachmentsFolder(in: folder).lastPathComponent
                == JournalAttachmentRules.folderName
        )
    }

    // MARK: - Réduction des images

    /// Une image PNG de la taille demandée, écrite dans le dossier.
    @MainActor
    private func writeImage(
        _ side: Int, named name: String, in folder: URL
    ) throws -> URL {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(
            data: image.tiffRepresentation!
        )!
        let url = folder.appending(path: name)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    @MainActor
    @Test("une grande photo est réduite sous le plafond")
    func alargePictureIsBroughtUnderTheCeiling() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeImage(3000, named: "grande.png", in: folder)

        let reduced = try #require(JournalFolder.reduced(at: source))
        let image = try #require(NSImage(data: reduced))
        #expect(max(image.size.width, image.size.height) <= 2048)
        // Et bien plus légère que l'original.
        let sourceSize = try FileManager.default
            .attributesOfItem(atPath: source.path)[.size] as! Int
        #expect(reduced.count < sourceSize)
    }

    @MainActor
    @Test("une image déjà petite n'est pas réencodée")
    func asmallPictureIsLeftAlone() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeImage(400, named: "petite.png", in: folder)

        // Nil veut dire « rien à faire » : réencoder ce qui ne coûte rien ne
        // ferait que perdre du détail, et c'est l'appelant qui garde alors les
        // octets d'origine, extension comprise.
        #expect(JournalFolder.reduced(at: source) == nil)
        #expect(JournalFolder.reduced(try Data(contentsOf: source)) == nil)
    }
}
