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
        // repris tels quels, un octet pour un caractère — sauf 0x00, seul
        // décalé vers U+E000, exactement ce que documente
        // `JournalImport.encodeBytesLosslessly`.
        let notes = try context.fetch(FetchDescriptor<JournalNote>())
        let unreadableNote = notes.first { $0.dateKeyRaw == "2026-08-17" }
        let expected = String(
            String.UnicodeScalarView(
                rawBytes.map { Unicode.Scalar($0 == 0 ? 0xE000 : UInt32($0))! }
            )
        )
        #expect(unreadableNote?.text == expected)
    }

    /// Critique : un fichier UTF-8 parfaitement valide, mais portant un octet
    /// NUL littéral, doit ressortir entier. `JournalFolder` le décode sans
    /// erreur (`isReadable == true`) : il ne passe jamais par la
    /// reconstruction depuis les octets bruts, seulement par la même
    /// substitution appliquée au texte lisible.
    @Test func uneNoteUTF8AvecUnOctetNulRessortEntiere() throws {
        let folder = try makeFolder(notes: [:])
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "avant\0apres"
        try Data(text.utf8).write(to: folder.appending(path: "2026-08-17.md"))
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(outcome?.notes == 1)
        #expect(outcome?.unreadable == [])
        let notes = try context.fetch(FetchDescriptor<JournalNote>())
        let note = notes.first { $0.dateKeyRaw == "2026-08-17" }
        // Les 11 caractères d'"avant\0apres" sont tous là — pas les 5 d'
        // "avant" seul, ce que rendrait la troncature au NUL si la
        // substitution n'avait pas eu lieu. Défaite avec la vraie fonction
        // inverse, pas un remplacement recalculé à la main.
        #expect(note?.text.unicodeScalars.count == 11)
        #expect(note.map { JournalImport.unescapingNUL($0.text) } == text)
    }

    /// Le couple qui protège chaque note du piège du NUL doit rester son
    /// propre inverse : l'un défait exactement ce que l'autre a fait,
    /// aller-retour de fonction à fonction plutôt que par un texte
    /// recalculé à la main — c'est ce que l'export de la tâche 5
    /// consommera.
    @Test func laSubstitutionDuNulEtSonInverseFontLAllerRetour() {
        let text = "avant\0apres, à bientôt — « citation »"
        #expect(JournalImport.unescapingNUL(JournalImport.escapingNUL(text)) == text)
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

    /// Une note encore un substitut iCloud non téléchargé ne doit ni entrer
    /// en base partiellement, ni marquer la reprise faite : sinon elle
    /// disparaîtrait du journal pour de bon dès qu'elle finirait par
    /// descendre. Les notes déjà arrivées ne doivent pas non plus rester
    /// dans le contexte malgré l'échec — c'est `context.rollback()` qui le
    /// garantit.
    @Test func unSubstitutICloudEnAttenteNeMarquePasEtDefaitSesInsertions() throws {
        let folder = try makeFolder(notes: ["2026-08-16": "arrivée"])
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: ".2026-08-17.md.icloud"))
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        #expect(throws: (any Error).self) {
            try JournalImport.runIfNeeded(context, folderPath: folder.path, defaults: defaults)
        }

        #expect(!defaults.bool(forKey: JournalSettings.importDoneKey))
        #expect(try context.fetch(FetchDescriptor<JournalNote>()).isEmpty)
    }

    /// Un fichier caché (`.DS_Store`) ne devient pas un `JournalAttachment` —
    /// l'extension est le filtre, la même liste qu'un dépôt ou un collage.
    @Test func unFichierCacheNeDevientPasUnePieceJointe() throws {
        let folder = try makeFolder(
            notes: [:],
            attachments: ["2026-08-17-1.jpg": Data(repeating: 0x7F, count: 4)]
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let sub = folder.appending(path: JournalAttachmentRules.folderName)
        try Data().write(to: sub.appending(path: ".DS_Store"))
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(outcome?.attachments == 1)
        #expect(try context.fetch(FetchDescriptor<JournalAttachment>()).count == 1)
    }

    /// Une image encore un substitut iCloud non téléchargé ne doit pas
    /// marquer la reprise faite : le trou fermé pour les notes existait
    /// aussi côté images, avant que `hasPendingDownloads` ne regarde
    /// `pieces-jointes/`.
    @Test func unSubstitutICloudDUneImageEnAttenteNeMarquePasFait() throws {
        let folder = try makeFolder(
            notes: [:], attachments: ["2026-08-17-1.jpg": Data(repeating: 0x7F, count: 4)]
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let sub = folder.appending(path: JournalAttachmentRules.folderName)
        try Data().write(to: sub.appending(path: ".2026-08-17-2.jpg.icloud"))
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        #expect(throws: (any Error).self) {
            try JournalImport.runIfNeeded(context, folderPath: folder.path, defaults: defaults)
        }

        #expect(!defaults.bool(forKey: JournalSettings.importDoneKey))
        #expect(try context.fetch(FetchDescriptor<JournalAttachment>()).isEmpty)
    }

    /// Un sous-dossier dans `pieces-jointes/` — improbable, mais pas
    /// impossible — ne doit pas faire échouer toute la reprise, et ne doit
    /// pas non plus disparaître sans laisser de trace : son nom passe le
    /// filtre d'extension, mais `Data(contentsOf:)` échoue sur un dossier.
    @Test func unSousDossierDansPiecesJointesNInterrompNienImporte() throws {
        let folder = try makeFolder(
            notes: [:],
            attachments: ["2026-08-17-1.jpg": Data(repeating: 0x7F, count: 4)]
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let sub = folder.appending(path: JournalAttachmentRules.folderName)
            .appending(path: "sub.jpg")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(outcome?.attachments == 1)
        #expect(outcome?.unreadable == ["sub.jpg"])
    }
}
