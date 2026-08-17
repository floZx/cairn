import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Export Markdown du journal")
struct JournalMarkdownExportTests {
    /// LA garantie de la tranche : un dossier repris puis réexporté est le
    /// même dossier. « Le même » veut dire : mêmes noms de fichiers, textes
    /// identiques au caractère près, images identiques aux octets près.
    /// Ni reformatage, ni réencodage, ni réécriture de lien.
    ///
    /// Chaque texte piège un exportateur trop zélé sur un point précis :
    /// avant-propos YAML, lignes vides et accents ("2026-08-16"), un lien
    /// d'image à ne pas réécrire ("2026-08-17"), l'absence de saut de ligne
    /// final ("2026-08-15"), des fins de ligne CRLF ("2026-08-14"), et un
    /// caractère U+E000 littéral ("2026-08-13") — celui-là même que
    /// `JournalImport.escapingNUL` utilise pour représenter un NUL, qui doit
    /// donc ressortir comme lui-même et non comme un octet nul.
    @Test func unDossierRepisPuisExporteEstLeMeme() throws {
        let source = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-aller-\(UUID().uuidString)")
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-retour-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let texts = [
            "2026-08-16": "---\ntitre: hier\n---\n\nUne sortie très longue.\n\n#course\n",
            "2026-08-17": "Aujourd'hui.\n\n![](pieces-jointes/2026-08-17-1.jpg)\n",
            "2026-08-15": "Pas de saut de ligne final, mais des accents : é è à ç ô.",
            "2026-08-14": "Fins de ligne CRLF.\r\nDeuxième ligne.\r\n",
            "2026-08-13": "Un caractère \u{E000} tapé par erreur, distinct du NUL.",
        ]
        for (name, text) in texts {
            try text.write(
                to: source.appending(path: "\(name).md"), atomically: true, encoding: .utf8
            )
        }
        let attachmentsFolder = source.appending(path: JournalAttachmentRules.folderName)
        try FileManager.default.createDirectory(
            at: attachmentsFolder, withIntermediateDirectories: true
        )
        let bytes = Data((0..<256).map { UInt8($0 % 256) })
        try bytes.write(to: attachmentsFolder.appending(path: "2026-08-17-1.jpg"))

        let defaults = UserDefaults(suiteName: "journal-roundtrip-\(UUID().uuidString)")!
        let context = ModelContext(try AppModelContainer.inMemory())
        _ = try JournalImport.runIfNeeded(
            context, folderPath: source.path, defaults: defaults
        )

        try JournalMarkdownExport.write(context, to: destination)

        // Les mêmes noms de notes.
        let exported = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(Set(exported.filter { $0.hasSuffix(".md") })
                    == Set(texts.keys.map { "\($0).md" }))

        // Les mêmes textes, au caractère près.
        for (name, text) in texts {
            let written = try String(
                contentsOf: destination.appending(path: "\(name).md"), encoding: .utf8
            )
            #expect(written == text)
        }

        // Les mêmes octets, y compris les fins de ligne CRLF et l'absence
        // de saut de ligne final, ce qu'une comparaison au caractère près
        // laisserait passer si l'export avait malgré tout ajouté ou changé
        // un octet invisible à l'affichage.
        for name in texts.keys {
            let sourceBytes = try Data(contentsOf: source.appending(path: "\(name).md"))
            let destinationBytes = try Data(contentsOf: destination.appending(path: "\(name).md"))
            #expect(destinationBytes == sourceBytes)
        }

        // Les mêmes octets d'image.
        let exportedImage = destination
            .appending(path: JournalAttachmentRules.folderName)
            .appending(path: "2026-08-17-1.jpg")
        #expect(try Data(contentsOf: exportedImage) == bytes)
    }

    /// Un journal vide produit un dossier vide, pas une erreur : la sauvegarde
    /// tourne aussi sur une installation qui n'a jamais pris de note.
    @Test func unJournalVideProduitUnDossierVide() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-vide-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let context = ModelContext(try AppModelContainer.inMemory())

        #expect(try JournalMarkdownExport.write(context, to: destination) == 0)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    /// Sans pièce jointe en base, `pieces-jointes/` n'est pas créé — un
    /// exportateur qui le crée systématiquement laisserait un dossier vide
    /// dans chaque sauvegarde d'un journal sans image.
    @Test func sansPieceJointeAucunDossierNEstCree() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-sans-images-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let context = ModelContext(try AppModelContainer.inMemory())
        context.insert(JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "sans image"))
        try context.save()

        try JournalMarkdownExport.write(context, to: destination)

        #expect(
            !FileManager.default.fileExists(
                atPath: destination.appending(path: JournalAttachmentRules.folderName).path
            )
        )
    }
}
