// Cairn/Features/Nutrition/CatalogCSV.swift
import Foundation

/// One line of the Open Food Facts CSV export, parsed and filtered — the
/// Swift port of the importer's `FILTER_SQL`. Pure string work, no I/O:
/// the builder streams lines through here.
enum CatalogCSV {
    struct Columns: Equatable {
        var code: Int
        var name: Int
        var brands: Int
        var quantity: Int
        var servingSize: Int
        var countriesTags: Int
        var completeness: Int
        var kcal: Int
        var protein: Int
        var carbs: Int
        var fat: Int
    }

    struct Row: Equatable {
        var code: String
        var name: String
        var brands: String?
        var quantity: String?
        var kcal: Double
        var protein: Double
        var carbs: Double?
        var fat: Double?
        var servingSize: String?
        var completeness: Double
    }

    struct HeaderError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static let completenessThreshold = 0.5

    /// Column indexes resolved by header name — the export's column order
    /// is not a contract, and a renamed column must fail loudly rather than
    /// silently reading the wrong data into the catalog.
    static func columns(from headerLine: String) throws -> Columns {
        let names = headerLine
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)
        func index(of name: String) throws -> Int {
            guard let index = names.firstIndex(of: name) else {
                throw HeaderError(
                    message: "Colonne « \(name) » introuvable dans l'export CSV."
                )
            }
            return index
        }
        return Columns(
            code: try index(of: "code"),
            name: try index(of: "product_name"),
            brands: try index(of: "brands"),
            quantity: try index(of: "quantity"),
            servingSize: try index(of: "serving_size"),
            countriesTags: try index(of: "countries_tags"),
            completeness: try index(of: "completeness"),
            kcal: try index(of: "energy-kcal_100g"),
            protein: try index(of: "proteins_100g"),
            carbs: try index(of: "carbohydrates_100g"),
            fat: try index(of: "fat_100g")
        )
    }

    /// nil = filtered out. The filters mirror `FILTER_SQL`: France only,
    /// name and code present, kcal/protein present, completeness ≥ 0.5,
    /// plausibility bounds (a kJ typed into the kcal field reads as 1500+).
    static func row(from line: String, columns: Columns) -> Row? {
        let fields = line
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)
        func field(_ index: Int) -> String? {
            guard fields.indices.contains(index) else { return nil }
            let value = fields[index]
            return value.isEmpty ? nil : value
        }
        guard let code = field(columns.code),
              let name = field(columns.name),
              let countries = field(columns.countriesTags),
              countries.split(separator: ",").contains("en:france"),
              let completeness = field(columns.completeness).flatMap(Double.init),
              completeness >= completenessThreshold,
              let kcal = field(columns.kcal).flatMap(Double.init),
              let protein = field(columns.protein).flatMap(Double.init),
              (0...900).contains(kcal),
              (0...100).contains(protein)
        else { return nil }
        let carbs = field(columns.carbs).flatMap(Double.init)
        let fat = field(columns.fat).flatMap(Double.init)
        if let carbs, !(0...100).contains(carbs) { return nil }
        if let fat, !(0...100).contains(fat) { return nil }
        return Row(
            code: code, name: name,
            brands: field(columns.brands),
            quantity: field(columns.quantity),
            kcal: kcal, protein: protein, carbs: carbs, fat: fat,
            servingSize: field(columns.servingSize),
            completeness: completeness
        )
    }
}
