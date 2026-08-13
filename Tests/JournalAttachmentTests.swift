import Testing
import Foundation
@testable import Cairn

@Suite("Les pièces jointes du journal")
struct JournalAttachmentTests {
    private let day = DateKey(raw: "2026-08-13")!

    @Test("le nom prend le premier numéro libre du jour")
    func nameTakesTheFirstFreeNumber() {
        #expect(
            JournalAttachment.fileName(for: day, extension: "jpg", taken: [])
                == "2026-08-13-1.jpg"
        )
        #expect(
            JournalAttachment.fileName(
                for: day, extension: "jpg",
                taken: ["2026-08-13-1.jpg", "2026-08-13-2.png"]
            ) == "2026-08-13-3.jpg"
        )
        // Le numéro est pris quelle que soit l'extension : deux fichiers qui ne
        // diffèrent que par elle se confondraient à la lecture.
        #expect(
            JournalAttachment.fileName(
                for: day, extension: "png", taken: ["2026-08-13-1.jpg"]
            ) == "2026-08-13-2.png"
        )
    }

    @Test("l'extension descend en minuscules")
    func theExtensionIsLowercased() {
        #expect(
            JournalAttachment.fileName(for: day, extension: "JPG", taken: [])
                == "2026-08-13-1.jpg"
        )
    }

    @Test("le lien est du Markdown standard, pas une syntaxe d'Obsidian")
    func thelinkIsPlainMarkdown() {
        #expect(
            JournalAttachment.link(to: "2026-08-13-1.jpg")
                == "![](pieces-jointes/2026-08-13-1.jpg)"
        )
    }

    @Test("la ligne s'ajoute à la fin sans doubler les sauts de ligne")
    func linksLandAtTheEnd() {
        let link = JournalAttachment.link(to: "2026-08-13-1.jpg")
        // Une note vide n'ouvre pas sur une ligne blanche.
        #expect(JournalAttachment.appending([link], to: "") == link)
        // Une note sans saut de ligne final en gagne un.
        #expect(
            JournalAttachment.appending([link], to: "Jambes lourdes.")
                == "Jambes lourdes.\n\n\(link)"
        )
        // Une note qui en a déjà n'en gagne pas deux.
        #expect(
            JournalAttachment.appending([link], to: "Jambes lourdes.\n\n")
                == "Jambes lourdes.\n\n\(link)"
        )
        // Un seul saut en gagne un second, pas trois.
        #expect(
            JournalAttachment.appending([link], to: "Jambes lourdes.\n")
                == "Jambes lourdes.\n\n\(link)"
        )
    }

    @Test("plusieurs fichiers donnent plusieurs lignes, dans l'ordre")
    func severalFilesKeepTheirOrder() {
        let first = JournalAttachment.link(to: "2026-08-13-1.jpg")
        let second = JournalAttachment.link(to: "2026-08-13-2.jpg")
        #expect(
            JournalAttachment.appending([first, second], to: "Note.")
                == "Note.\n\n\(first)\n\(second)"
        )
        // Aucune ligne à ajouter ne touche pas au texte.
        #expect(JournalAttachment.appending([], to: "Note.") == "Note.")
    }

    @Test("seules les images entrent")
    func onlyImagesAreAccepted() {
        #expect(JournalAttachment.allowedExtensions.contains("jpg"))
        #expect(JournalAttachment.allowedExtensions.contains("jpeg"))
        #expect(JournalAttachment.allowedExtensions.contains("png"))
        #expect(JournalAttachment.allowedExtensions.contains("heic"))
        #expect(!JournalAttachment.allowedExtensions.contains("pdf"))
        #expect(!JournalAttachment.allowedExtensions.contains("md"))
    }
}
