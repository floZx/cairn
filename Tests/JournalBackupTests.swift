import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Le journal dans la sauvegarde")
struct JournalBackupTests {
    /// La sauvegarde écrit le journal en Markdown à côté de la base, sans quoi
    /// la promesse « vos notes ressortent en Markdown » ne tient que si on y
    /// pense — c'est-à-dire jamais.
    @Test func laSauvegardeEcritLeJournalEnMarkdown() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "sauvegardée")
        context.insert(note)
        try context.save()

        try BackupService.writeJournalMarkdown(context, into: destination, stamp: "2026-08-17-0900")

        let folder = destination.appending(path: "journal-markdown-2026-08-17-0900")
        let text = try String(
            contentsOf: folder.appending(path: "2026-08-17.md"), encoding: .utf8
        )
        #expect(text == "sauvegardée")
    }

    /// `rotate` doit garder trois exemplaires de chaque famille séparément :
    /// un dossier `journal-markdown-…` a le préfixe `journal-` lui aussi, et
    /// se glisserait dans le même tri alphabétique que les `.sqlite.gz` si
    /// les deux n'étaient pas comptés à part — au risque d'effacer une base
    /// encore utile pour garder un export Markdown surnuméraire, ou l'inverse.
    ///
    /// `BackupService.rotate` est appelée pour de vrai, sur un vrai dossier :
    /// la version précédente de ce test refaisait le filtrage elle-même
    /// (`hasSuffix(".sqlite.gz")`) au lieu d'appeler la fonction, dont le
    /// filtre réel est `hasPrefix("journal-") && !hasPrefix(markdownPrefix)`.
    /// Elle serait restée verte devant une rotation fausse — sur le seul code
    /// de ce fichier qui **supprime des sauvegardes**.
    @Test func laRotationCompteLesDeuxFamillesSeparement() throws {
        let manager = FileManager.default
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "backup-rotation-\(UUID().uuidString)")
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: destination) }

        // Quatre bases et deux exports : la politique en garde trois de
        // chaque, donc seule la base la plus ancienne doit disparaître. Un
        // tri unique aurait, lui, emporté un export encore utile — les
        // dossiers `journal-markdown-…` se glissant entre les `journal-…`.
        let snapshots = [
            "journal-2026-08-14-0900.sqlite.gz",
            "journal-2026-08-15-0900.sqlite.gz",
            "journal-2026-08-16-0900.sqlite.gz",
            "journal-2026-08-17-0900.sqlite.gz",
        ]
        for name in snapshots {
            try Data([0x00]).write(to: destination.appending(path: name))
        }
        let exports = ["journal-markdown-2026-08-14-0900", "journal-markdown-2026-08-15-0900"]
        for name in exports {
            try manager.createDirectory(
                at: destination.appending(path: name), withIntermediateDirectories: true
            )
        }
        // Ni base ni export : rien de ce que la rotation gère n'a le droit de
        // l'emporter.
        try "restaurer".write(
            to: destination.appending(path: "COMMENT-RESTAURER.txt"),
            atomically: true, encoding: .utf8
        )

        BackupService.rotate(in: destination)

        let left = Set(try manager.contentsOfDirectory(atPath: destination.path))
        #expect(left == Set(Array(snapshots.dropFirst()) + exports + ["COMMENT-RESTAURER.txt"]))
    }
}
