import Testing
import Foundation
import SwiftData
@testable import Cairn

/// The cache reconstructs what is missing on disk from what the store holds.
///
/// Every test that writes bytes passes its own throwaway directory rather
/// than `JournalAttachmentCache.directory`: that property names the
/// application's real cache folder, and a test run must never leave files
/// there, exactly as `Tests/JournalStoreTests.swift` never points a store at
/// the user's real journal folder.
@Suite("Cache des pièces jointes")
struct JournalAttachmentCacheTests {
    /// A throwaway directory, discarded by the caller.
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-attachment-cache-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    private func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Le cache reconstruit ce qui manque, et rend le compte de ce qu'il a
    /// écrit — c'est ce qui le rend testable et son idempotence vérifiable.
    @Test func laReconstructionEcritCeQuiManque() throws {
        let directory = try makeDirectory()
        defer { discard(directory) }
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(
            JournalAttachment(
                fileName: "2026-08-17-1.jpg", data: Data(repeating: 0x01, count: 8)
            )
        )
        try context.save()

        let written = try JournalAttachmentCache.rebuild(context, directory: directory)
        #expect(written == 1)

        let url = directory.appending(path: "2026-08-17-1.jpg")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == Data(repeating: 0x01, count: 8))
    }

    /// Relancée, elle n'écrit rien : le fichier est déjà là. Sans quoi chaque
    /// lancement réécrirait toutes les images du journal.
    @Test func laReconstructionEstIdempotente() throws {
        let directory = try makeDirectory()
        defer { discard(directory) }
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(
            JournalAttachment(
                fileName: "2026-08-17-2.jpg", data: Data(repeating: 0x02, count: 8)
            )
        )
        try context.save()

        _ = try JournalAttachmentCache.rebuild(context, directory: directory)
        #expect(try JournalAttachmentCache.rebuild(context, directory: directory) == 0)
    }

    /// Une pièce jointe sans octets ne produit aucun fichier — et surtout
    /// aucun fichier vide, qui se lirait comme une image corrompue. Ce test
    /// ne passe aucun répertoire jetable : `materialise` doit renvoyer nil
    /// avant même de songer à écrire quoi que ce soit sur disque.
    @Test func unePieceSansOctetsNeProduitAucunFichier() throws {
        let attachment = JournalAttachment(fileName: "vide.jpg", data: Data())
        attachment.data = nil
        #expect(try JournalAttachmentCache.materialise(attachment) == nil)
    }

    /// `materialise` écrit sous le répertoire jetable qu'on lui passe, jamais
    /// sous le vrai dossier de cache de l'application.
    @Test func materialiseEcritSousLeRepertoireFourni() throws {
        let directory = try makeDirectory()
        defer { discard(directory) }
        let attachment = JournalAttachment(
            fileName: "2026-08-17-3.jpg", data: Data(repeating: 0x03, count: 4)
        )

        let url = try JournalAttachmentCache.materialise(attachment, directory: directory)
        #expect(url == directory.appending(path: "2026-08-17-3.jpg"))
        #expect(try Data(contentsOf: try #require(url)) == Data(repeating: 0x03, count: 4))
    }
}
