import Testing
import Foundation
@testable import Cairn

@Suite("Migration depuis l'ancien nom")
struct LegacyStoreMigrationTests {
    /// A throwaway pair of directories; the old one pre-filled with `entries`.
    private func makeDirectories(
        legacy entries: [String: String]
    ) throws -> (legacy: URL, destination: URL) {
        // A space in the path on purpose: the real library sits under
        // "Application Support", and a percent-encoded path made the first
        // version of this migration silently skip every file.
        let root = URL.temporaryDirectory
            .appending(path: "Application Support \(UUID().uuidString)")
        let legacy = root.appending(path: "StravaLocal")
        let destination = root.appending(path: "Cairn")
        for directory in [legacy, destination] {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        }
        for (name, contents) in entries {
            try contents.write(
                to: legacy.appending(path: name), atomically: true, encoding: .utf8
            )
        }
        return (legacy, destination)
    }

    @Test("le store, ses annexes et le dossier _SUPPORT sont renommés ensemble")
    func movesStoreAndSupport() throws {
        let (legacy, destination) = try makeDirectories(legacy: [
            "StravaLocal.store": "base",
            "StravaLocal.store-wal": "wal",
            "StravaLocal.store-shm": "shm",
            ".StravaLocal_SUPPORT": "blobs",
            "StravaLocal-demo.store": "demo",
        ])

        let moved = try LegacyStoreMigration.run(from: legacy, to: destination)

        #expect(moved == [
            ".Cairn_SUPPORT", "Cairn-demo.store",
            "Cairn.store", "Cairn.store-shm", "Cairn.store-wal",
        ])
        let contents = try String(
            contentsOf: destination.appending(path: "Cairn.store"), encoding: .utf8
        )
        #expect(contents == "base")
        // The support folder carries the external blobs and is found from the
        // store's own name, so a store renamed without it loses every track.
        #expect(
            try String(
                contentsOf: destination.appending(path: ".Cairn_SUPPORT"), encoding: .utf8
            ) == "blobs"
        )
        #expect(!FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
    }

    @Test("un store Cairn déjà présent n'est jamais écrasé")
    func neverOverwritesTheLiveStore() throws {
        let (legacy, destination) = try makeDirectories(legacy: ["StravaLocal.store": "ancien"])
        try "en cours".write(
            to: destination.appending(path: "Cairn.store"), atomically: true, encoding: .utf8
        )

        let moved = try LegacyStoreMigration.run(from: legacy, to: destination)

        #expect(moved.isEmpty)
        #expect(
            try String(
                contentsOf: destination.appending(path: "Cairn.store"), encoding: .utf8
            ) == "en cours"
        )
        // Left where it was rather than deleted: nothing should throw away a
        // library the app has decided not to adopt.
        #expect(
            FileManager.default.fileExists(
                atPath: legacy.appending(path: "StravaLocal.store")
                    .path(percentEncoded: false)
            )
        )
    }

    @Test("un store Cairn vide de 0 octet ne bloque pas la reprise")
    func stepsOverAnEmptyPlaceholder() throws {
        let (legacy, destination) = try makeDirectories(legacy: ["StravaLocal.store": "vraies données"])
        // Exactly what a stray `sqlite3 Cairn.store` leaves behind. Treated as a
        // real store, it locks the 132 Mo library out of the app for good.
        FileManager.default.createFile(
            atPath: destination.appending(path: "Cairn.store").path(percentEncoded: false),
            contents: Data()
        )

        #expect(try LegacyStoreMigration.run(from: legacy, to: destination) == ["Cairn.store"])
        #expect(
            try String(
                contentsOf: destination.appending(path: "Cairn.store"), encoding: .utf8
            ) == "vraies données"
        )
    }

    @Test("les fichiers étrangers sont laissés sur place")
    func ignoresUnrelatedFiles() throws {
        let (legacy, destination) = try makeDirectories(legacy: ["notes.txt": "rien à voir"])

        #expect(try LegacyStoreMigration.run(from: legacy, to: destination).isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: legacy.appending(path: "notes.txt").path(percentEncoded: false)
            )
        )
    }

    @Test("sans ancien dossier, la migration ne fait rien")
    func doesNothingWithoutALegacyDirectory() throws {
        let root = URL.temporaryDirectory
            .appending(path: "Application Support \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(
            try LegacyStoreMigration.run(
                from: root.appending(path: "StravaLocal"), to: root
            ).isEmpty
        )
    }
}
