import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Reprise du journal")
struct JournalImportTests {
    /// Un dossier jetable, avec ses notes et ses images.
    private func makeFolder(
        notes: [String: String], attachments: [String: Data] = [:]
    ) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, text) in notes {
            try text.write(
                to: url.appending(path: "\(name).md"), atomically: true, encoding: .utf8
            )
        }
        if !attachments.isEmpty {
            let sub = url.appending(path: JournalAttachmentRules.folderName)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for (name, bytes) in attachments {
                try bytes.write(to: sub.appending(path: name))
            }
        }
        return url
    }

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "journal-import-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func discard(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    /// Le cas nominal : les notes et les images entrent en base.
    @Test func laRepriseLitLesNotesEtLesImages() throws {
        let folder = try makeFolder(
            notes: ["2026-08-16": "hier", "2026-08-17": "aujourd'hui #course"],
            attachments: ["2026-08-17-1.jpg": Data(repeating: 0x7F, count: 16)]
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(outcome?.notes == 2)
        #expect(outcome?.attachments == 1)
        #expect(try context.fetch(FetchDescriptor<JournalNote>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<JournalAttachment>()).count == 1)
    }

    /// Relancée, elle ne fait rien du tout — pas « rien de nouveau », rien.
    /// C'est le marqueur qui l'arrête, pas un dédoublonnage.
    @Test func laRepriseNeSeFaitQuUneFois() throws {
        let folder = try makeFolder(notes: ["2026-08-17": "une note"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        _ = try JournalImport.runIfNeeded(context, folderPath: folder.path, defaults: defaults)
        let second = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(second == nil)
        #expect(try context.fetch(FetchDescriptor<JournalNote>()).count == 1)
    }

    /// Un dossier introuvable ne se marque PAS fait : un disque débranché ou
    /// un iCloud pas encore descendu perdrait tout le journal.
    @Test func unDossierIntrouvableNeSeMarquePasFait() throws {
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())
        let absent = "/tmp/journal-qui-nexiste-pas-\(UUID().uuidString)"

        _ = try? JournalImport.runIfNeeded(context, folderPath: absent, defaults: defaults)

        // Le dossier revient : la reprise doit encore avoir lieu.
        let folder = try makeFolder(notes: ["2026-08-17": "retrouvée"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )
        #expect(outcome?.notes == 1)
    }

    /// Aucun dossier n'a jamais été désigné : marqueur posé tout de suite,
    /// rien à faire, et jamais rien à refaire.
    @Test func sansDossierLaRepriseSeMarqueFaiteImmediatement() throws {
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let first = try JournalImport.runIfNeeded(context, folderPath: nil, defaults: defaults)
        #expect(first?.notes == 0)

        let second = try JournalImport.runIfNeeded(context, folderPath: nil, defaults: defaults)
        #expect(second == nil)
    }

    /// Un fichier illisible est repris quand même, ses octets conservés, et
    /// signalé. Boucler dessus indéfiniment serait pire.
    @Test func unFichierIllisibleEstRepisEtSignale() throws {
        let folder = try makeFolder(notes: ["2026-08-16": "lisible"])
        defer { try? FileManager.default.removeItem(at: folder) }
        // Des octets qui ne sont pas de l'UTF-8 valide.
        let rawBytes = Data([0xFF, 0xFE, 0x00, 0x01])
        try rawBytes.write(to: folder.appending(path: "2026-08-17.md"))
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(outcome?.unreadable == ["2026-08-17.md"])
        #expect(outcome?.notes == 2)
        // Pas une chaîne vide, pas des points d'interrogation : les octets
        // repris tels quels, un octet pour un caractère du plan privé
        // Unicode (U+E000...), exactement ce que documente
        // `JournalImport.encodeBytesLosslessly`.
        let notes = try context.fetch(FetchDescriptor<JournalNote>())
        let unreadableNote = notes.first { $0.dateKeyRaw == "2026-08-17" }
        let expected = String(
            String.UnicodeScalarView(rawBytes.map { Unicode.Scalar(0xE000 + UInt32($0))! })
        )
        #expect(unreadableNote?.text == expected)
    }

    /// Un dossier désigné mais vide — jamais une note écrite dedans — se
    /// marque fait comme n'importe quel autre : sinon la reprise
    /// réessaierait indéfiniment un dossier où il n'y a rien à trouver.
    @Test func unDossierVideSeMarqueFaiteAussi() throws {
        let folder = try makeFolder(notes: [:])
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let first = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )
        #expect(first?.notes == 0)

        let second = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )
        #expect(second == nil)
    }
}
