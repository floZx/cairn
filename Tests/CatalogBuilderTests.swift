// Tests/CatalogBuilderTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("CatalogBuilder")
@MainActor
struct CatalogBuilderTests {
    /// Writes a TSV, gzips it with the system gzip, returns the .gz path.
    private func makeFixture(lines: [String]) throws -> (gz: String, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let tsv = dir.appending(path: "food.csv")
        try lines.joined(separator: "\n").write(
            to: tsv, atomically: true, encoding: .utf8
        )
        let gzip = Process()
        gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzip.arguments = [tsv.path]
        try gzip.run()
        gzip.waitUntilExit()
        #expect(gzip.terminationStatus == 0)
        return (tsv.path + ".gz", dir)
    }

    private static let header = [
        "code", "product_name", "brands", "quantity", "serving_size",
        "countries_tags", "completeness", "energy-kcal_100g", "proteins_100g",
        "carbohydrates_100g", "fat_100g",
    ].joined(separator: "\t")

    private func product(
        code: String, name: String, countries: String = "en:france"
    ) -> String {
        [code, name, "Marque", "500 g", "40 g", countries, "0.9",
         "370", "13", "60", "7"].joined(separator: "\t")
    }

    @Test("le build filtre, indexe et bascule atomiquement")
    func buildsSearchableCatalog() throws {
        let (gz, dir) = try makeFixture(lines: [
            Self.header,
            product(code: "1", name: "Flocons d'avoine"),
            product(code: "2", name: "Bloemkool", countries: "en:belgium"),
            product(code: "3", name: "Crème fraîche"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let offDB = dir.appending(path: "off.db").path

        let count = try CatalogBuilder.build(
            gzPath: gz, offDBPath: offDB, importedAt: "2026-08-08"
        )

        #expect(count == 2)
        // Pas de .tmp résiduel après la bascule.
        #expect(!FileManager.default.fileExists(atPath: offDB + ".tmp"))
        let catalog = try FoodCatalog(path: offDB)
        #expect(try catalog.productCount() == 2)
        #expect(try catalog.search("floc").count == 1)
        #expect(try catalog.search("creme").count == 1)
        #expect(try catalog.search("bloemkool").isEmpty)
        #expect(try catalog.importedAt() == "2026-08-08")
    }

    @Test("un en-tête invalide échoue sans toucher au catalogue existant")
    func badHeaderLeavesExistingCatalogAlone() throws {
        let (gz, dir) = try makeFixture(lines: [
            "colonne\tinconnue", "1\t2",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let offDB = dir.appending(path: "off.db").path
        try Data("ancien catalogue".utf8).write(
            to: URL(fileURLWithPath: offDB))

        #expect(throws: (any Error).self) {
            _ = try CatalogBuilder.build(
                gzPath: gz, offDBPath: offDB, importedAt: "2026-08-08"
            )
        }
        // Le fichier courant n'a pas bougé, le .tmp a été nettoyé.
        #expect(try String(
            contentsOf: URL(fileURLWithPath: offDB), encoding: .utf8
        ) == "ancien catalogue")
        #expect(!FileManager.default.fileExists(atPath: offDB + ".tmp"))
    }

    @Test("un gz corrompu échoue proprement")
    func corruptGzFails() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let gz = dir.appending(path: "food.csv.gz")
        try Data("pas du gzip".utf8).write(to: gz)

        #expect(throws: (any Error).self) {
            _ = try CatalogBuilder.build(
                gzPath: gz.path,
                offDBPath: dir.appending(path: "off.db").path,
                importedAt: "2026-08-08"
            )
        }
    }

    @Test("la progression remonte lignes vues et produits gardés")
    func progressReportsCounts() throws {
        let (gz, dir) = try makeFixture(lines: [
            Self.header,
            product(code: "1", name: "Un"),
            product(code: "2", name: "Deux", countries: "en:spain"),
            product(code: "3", name: "Trois"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        final class Box: @unchecked Sendable { var last: (Int, Int) = (0, 0) }
        let box = Box()
        _ = try CatalogBuilder.build(
            gzPath: gz, offDBPath: dir.appending(path: "off.db").path,
            importedAt: "2026-08-08",
            onProgress: { lines, kept in box.last = (lines, kept) }
        )
        #expect(box.last.0 == 3)
        #expect(box.last.1 == 2)
    }
}
