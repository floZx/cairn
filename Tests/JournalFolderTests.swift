import Testing
import AppKit
import Foundation
@testable import Cairn

/// What is left of the folder: naming a day's file, and bringing a picture
/// down to size.
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
