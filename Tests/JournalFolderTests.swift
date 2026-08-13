import Testing
import Foundation
@testable import Cairn

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

    @Test("aller-retour écriture puis lecture")
    func writeThenRead() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try JournalFolder.write(
            "Promenade avec #Sam.", for: DateKey(raw: "2026-08-11")!, in: folder
        )
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
        try JournalFolder.write("bon", for: DateKey(raw: "2026-08-11")!, in: folder)

        let notes = try JournalFolder.notes(in: folder)
        #expect(notes.map(\.date.raw) == ["2026-08-11"])
        #expect(notes[0].text == "bon")
    }

    @Test("les notes sortent de la plus récente à la plus ancienne")
    func notesAreSortedNewestFirst() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        for raw in ["2026-08-09", "2026-08-11", "2026-08-10"] {
            try JournalFolder.write(raw, for: DateKey(raw: raw)!, in: folder)
        }
        #expect(
            try JournalFolder.notes(in: folder).map(\.date.raw)
                == ["2026-08-11", "2026-08-10", "2026-08-09"]
        )
    }

    @Test("une suppression hors corbeille efface le fichier")
    func removeWithoutTrash() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let date = DateKey(raw: "2026-08-11")!
        try JournalFolder.write("x", for: date, in: folder)
        try JournalFolder.remove(date, in: folder, toTrash: false)
        #expect(try JournalFolder.notes(in: folder).isEmpty)
    }

    @Test("supprimer une note absente ne lève pas")
    func removingAMissingNoteIsSilent() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try JournalFolder.remove(DateKey(raw: "2026-08-11")!, in: folder, toTrash: false)
    }

    @Test("un fichier illisible est listé plutôt qu'omis")
    func undecodableFileIsStillListed() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // 0xFF 0xFE 0xFF 0xFE is not valid UTF-8, so decoding fails and the
        // note is listed with isReadable: false instead — there is no
        // fallback encoding.
        try Data([0xFF, 0xFE, 0xFF, 0xFE]).write(
            to: folder.appending(path: "2026-08-11.md")
        )
        let notes = try JournalFolder.notes(in: folder)
        #expect(notes.count == 1)
        #expect(notes[0].summary == "contenu illisible")
    }

    @Test("un espace réservé iCloud non téléchargé n'est pas listé")
    func iCloudPlaceholderIsNotListed() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try JournalFolder.write("réelle", for: DateKey(raw: "2026-08-10")!, in: folder)
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

    // MARK: - Pièces jointes

    @Test("une pièce jointe copiée prend son nom du jour")
    func acopiedAttachmentIsRenamed() throws {
        let folder = try makeFolder()
        let source = folder.appending(path: "IMG_4032.JPG")
        try Data([0xFF, 0xD8]).write(to: source)

        let name = try JournalFolder.copyAttachment(
            from: source, for: DateKey(raw: "2026-08-13")!, in: folder
        )
        #expect(name == "2026-08-13-1.jpg")

        let written = JournalFolder.attachmentsFolder(in: folder)
            .appending(path: name)
        #expect(FileManager.default.fileExists(atPath: written.path))
        // L'original n'est pas déplacé : la photo reste où elle était.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("deux pièces jointes du même jour ne se marchent pas dessus")
    func twoAttachmentsOfTheSameDayCoexist() throws {
        let folder = try makeFolder()
        let day = DateKey(raw: "2026-08-13")!
        let first = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png", for: day, in: folder
        )
        let second = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png", for: day, in: folder
        )
        #expect(first == "2026-08-13-1.png")
        #expect(second == "2026-08-13-2.png")
    }

    @Test("le dossier des pièces jointes se crée au besoin")
    func theattachmentsFolderIsCreated() throws {
        let folder = try makeFolder()
        let attachments = JournalFolder.attachmentsFolder(in: folder)
        #expect(!FileManager.default.fileExists(atPath: attachments.path))

        _ = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png",
            for: DateKey(raw: "2026-08-13")!, in: folder
        )
        #expect(FileManager.default.fileExists(atPath: attachments.path))
    }

    @Test("une pièce jointe n'est pas une note")
    func anattachmentIsNotANote() throws {
        let folder = try makeFolder()
        try JournalFolder.write("Note.", for: DateKey(raw: "2026-08-13")!, in: folder)
        _ = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png",
            for: DateKey(raw: "2026-08-13")!, in: folder
        )
        // Le listing est plat par nature : le sous-dossier n'y entre pas.
        #expect(try JournalFolder.notes(in: folder).count == 1)
    }
}
