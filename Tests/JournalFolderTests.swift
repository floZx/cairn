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
}
