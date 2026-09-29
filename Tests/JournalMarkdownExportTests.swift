import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Export Markdown du journal")
struct JournalMarkdownExportTests {
    /// LA garantie de l'export : ce qu'on écrit ressort tel quel. Mêmes noms
    /// de fichiers, textes identiques au caractère près, images identiques
    /// aux octets près. Ni reformatage, ni réencodage, ni réécriture de lien.
    ///
    /// Chaque texte piège un exportateur trop zélé, ou la paire
    /// d'échappement du NUL, sur un point précis :
    /// - avant-propos YAML, lignes vides et accents ("2026-08-16") ;
    /// - un lien d'image à ne pas réécrire ("2026-08-17") ;
    /// - l'absence de saut de ligne final ("2026-08-15") ;
    /// - des fins de ligne CRLF ("2026-08-14") ;
    /// - un U+E000 littéral ("2026-08-13") — le marqueur que
    ///   `JournalNUL.escapingNUL` utilise pour représenter un NUL ;
    /// - un U+E001 littéral ("2026-08-12") — le désambiguïsateur de ce même
    ///   marqueur ;
    /// - un NUL réel ("2026-08-11").
    ///
    /// Les notes entrent en base comme la reprise de l'ancien dossier les y
    /// avait mises, échappées : c'est ce que l'export doit défaire.
    @Test func ceQuiEstEcritRessortTelQuel() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-retour-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }

        let texts = [
            "2026-08-16": "---\ntitre: hier\n---\n\nUne sortie très longue.\n\n#course\n",
            "2026-08-17": "Aujourd'hui.\n\n![](pieces-jointes/2026-08-17-1.jpg)\n",
            "2026-08-15": "Pas de saut de ligne final, mais des accents : é è à ç ô.",
            "2026-08-14": "Fins de ligne CRLF.\r\nDeuxième ligne.\r\n",
            "2026-08-13": "Un caractère \u{E000} tapé par erreur, distinct du NUL.",
            "2026-08-12": "Un caractère \u{E001} tapé par erreur aussi, distinct des deux autres.",
            "2026-08-11": "avant\0après un octet nul réel, pas un caractère qui lui ressemble.",
        ]
        let context = ModelContext(try AppModelContainer.inMemory())
        for (day, text) in texts {
            context.insert(JournalNote(dateKey: DateKey(raw: day)!, text: JournalNUL.escapingNUL(text)))
        }
        let bytes = Data((0..<256).map { UInt8($0 % 256) })
        context.insert(JournalAttachment(fileName: "2026-08-17-1.jpg", data: bytes))
        try context.save()

        try JournalMarkdownExport.write(context, to: destination)

        // Les mêmes noms de notes.
        let exported = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(Set(exported.filter { $0.hasSuffix(".md") })
                    == Set(texts.keys.map { "\($0).md" }))

        // Les mêmes octets, y compris les fins de ligne CRLF et l'absence de
        // saut de ligne final.
        for (name, text) in texts {
            let written = try Data(contentsOf: destination.appending(path: "\(name).md"))
            #expect(written == Data(text.utf8))
        }

        // Les mêmes pièces jointes, en ensemble : une image en trop en
        // sortie passerait inaperçue à ne vérifier que celle qu'on attend.
        let exportedAttachments = try FileManager.default.contentsOfDirectory(
            atPath: destination.appending(path: JournalAttachmentRules.folderName).path
        )
        #expect(Set(exportedAttachments) == ["2026-08-17-1.jpg"])

        // Les mêmes octets d'image.
        let exportedImage = destination
            .appending(path: JournalAttachmentRules.folderName)
            .appending(path: "2026-08-17-1.jpg")
        #expect(try Data(contentsOf: exportedImage) == bytes)
    }

    /// Un journal vide produit un dossier vide, pas une erreur : la sauvegarde
    /// tourne aussi sur une installation qui n'a jamais pris de note. « Vide »
    /// veut dire vide : un dossier réel, sans rien dedans, pas seulement un
    /// chemin qui existe.
    @Test func unJournalVideProduitUnDossierVide() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-vide-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let context = ModelContext(try AppModelContainer.inMemory())

        #expect(try JournalMarkdownExport.write(context, to: destination) == 0)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
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
