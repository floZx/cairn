// Tests/CatalogCSVTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("CatalogCSV")
struct CatalogCSVTests {
    private static let header = [
        "code", "url", "product_name", "brands", "quantity", "serving_size",
        "countries_tags", "completeness", "energy-kcal_100g", "proteins_100g",
        "carbohydrates_100g", "fat_100g",
    ].joined(separator: "\t")

    /// A line in the fixture header's order, with sensible defaults.
    private func line(
        code: String = "123", name: String = "Flocons d'avoine",
        brands: String = "Marque A", countries: String = "en:france,en:belgium",
        completeness: String = "0.9", kcal: String = "370",
        protein: String = "13", carbs: String = "60", fat: String = "7"
    ) -> String {
        [
            code, "https://exemple", name, brands, "500 g", "40 g",
            countries, completeness, kcal, protein, carbs, fat,
        ].joined(separator: "\t")
    }

    private func columns() throws -> CatalogCSV.Columns {
        try CatalogCSV.columns(from: Self.header)
    }

    @Test("les colonnes se résolvent par nom, pas par position")
    func columnsResolveByName() throws {
        let columns = try columns()
        // "url" est intercalée : les index doivent la sauter.
        #expect(columns.code == 0)
        #expect(columns.name == 2)
        #expect(columns.kcal == 8)
        #expect(columns.fat == 11)
    }

    @Test("une colonne manquante échoue en la nommant")
    func missingColumnThrowsWithName() {
        #expect(throws: CatalogCSV.HeaderError.self) {
            _ = try CatalogCSV.columns(from: "code\tproduct_name\tbrands")
        }
        do {
            _ = try CatalogCSV.columns(from: "code\tproduct_name\tbrands")
        } catch let error as CatalogCSV.HeaderError {
            #expect(error.message.contains("quantity"))
        } catch {
            Issue.record("mauvais type d'erreur")
        }
    }

    @Test("une ligne française complète passe avec ses valeurs")
    func frenchCompleteRowParses() throws {
        let row = try #require(CatalogCSV.row(from: line(), columns: columns()))
        #expect(row.code == "123")
        #expect(row.name == "Flocons d'avoine")
        #expect(row.brands == "Marque A")
        #expect(row.kcal == 370)
        #expect(row.protein == 13)
        #expect(row.carbs == 60)
        #expect(row.fat == 7)
        #expect(row.servingSize == "40 g")
        #expect(row.completeness == 0.9)
    }

    @Test("hors France, filtré — même si 'france' apparaît ailleurs")
    func nonFranceFiltered() throws {
        let columns = try columns()
        #expect(CatalogCSV.row(
            from: line(countries: "en:belgium"), columns: columns
        ) == nil)
        // "en:french-guiana" contient "france" mais n'est pas le tag exact.
        #expect(CatalogCSV.row(
            from: line(countries: "en:french-guiana"), columns: columns
        ) == nil)
    }

    @Test("nom vide, code vide, kcal ou protéines absents : filtrés")
    func requiredFieldsFilter() throws {
        let columns = try columns()
        #expect(CatalogCSV.row(from: line(name: ""), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(code: ""), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(kcal: ""), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(protein: ""), columns: columns) == nil)
    }

    @Test("complétude insuffisante ou absente : filtrée")
    func completenessFilter() throws {
        let columns = try columns()
        #expect(CatalogCSV.row(
            from: line(completeness: "0.4"), columns: columns
        ) == nil)
        #expect(CatalogCSV.row(
            from: line(completeness: ""), columns: columns
        ) == nil)
        #expect(CatalogCSV.row(
            from: line(completeness: "0.5"), columns: columns
        ) != nil)
    }

    @Test("bornes de vraisemblance : kcal 0-900, macros 0-100")
    func plausibilityBounds() throws {
        let columns = try columns()
        // 1500 "kcal" est un kJ saisi dans le mauvais champ.
        #expect(CatalogCSV.row(from: line(kcal: "1500"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(kcal: "-1"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(protein: "120"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(carbs: "101"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(fat: "-2"), columns: columns) == nil)
        // Glucides/lipides absents restent acceptés, en nil.
        let sparse = try #require(CatalogCSV.row(
            from: line(carbs: "", fat: ""), columns: columns
        ))
        #expect(sparse.carbs == nil)
        #expect(sparse.fat == nil)
    }

    @Test("brands et serving_size vides deviennent nil")
    func emptyOptionalsBecomeNil() throws {
        let columns = try columns()
        let row = try #require(CatalogCSV.row(
            from: [
                "123", "u", "Riz", "", "", "", "en:france", "0.8",
                "350", "7", "", "",
            ].joined(separator: "\t"),
            columns: columns
        ))
        #expect(row.brands == nil)
        #expect(row.servingSize == nil)
        #expect(row.quantity == nil)
    }

    @Test("une ligne trop courte est filtrée sans crash")
    func shortLineFiltered() throws {
        #expect(CatalogCSV.row(from: "123\tabc", columns: try columns()) == nil)
    }
}
