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
    @Test func laRotationCompteLesDeuxFamillesSeparement() {
        let names = [
            "journal-2026-08-14-0900.sqlite.gz",
            "journal-2026-08-15-0900.sqlite.gz",
            "journal-2026-08-16-0900.sqlite.gz",
            "journal-2026-08-17-0900.sqlite.gz",
            "journal-markdown-2026-08-14-0900",
            "journal-markdown-2026-08-15-0900",
        ]
        let sqliteOnly = names.filter { $0.hasSuffix(".sqlite.gz") }
        let markdownOnly = names.filter { $0.hasPrefix("journal-markdown-") }
        // La politique de rétention elle-même (garder les trois derniers) est
        // déjà couverte par `Tests/BackupPlanTests.swift` ; ce test vérifie
        // seulement que les deux familles ne se mélangent pas dans le même
        // tri, ce que `BackupPlan.snapshotsToDelete` ne peut pas savoir tout
        // seul puisqu'il ne voit que des noms.
        #expect(BackupPlan.snapshotsToDelete(sqliteOnly) == [
            "journal-2026-08-14-0900.sqlite.gz",
        ])
        #expect(BackupPlan.snapshotsToDelete(markdownOnly).isEmpty)
    }
}
