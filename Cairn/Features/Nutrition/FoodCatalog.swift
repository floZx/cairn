import Foundation

/// Read-only access to the Open Food Facts catalog (`off.db`), the same
/// SQLite FTS5 file suivinut builds. Kept outside SwiftData on purpose:
/// 180k products and diacritics-insensitive prefix search are FTS5's
/// terrain. Ported from suivinut's `db/catalog.py:search`.
@MainActor
final class FoodCatalog {
    struct Product: Equatable {
        var code: String
        var name: String
        var brands: String
        var kcal100: Double
        var protein100: Double
        var carbs100: Double
        var fat100: Double
        var servingSize: String?
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Cairn/off.db")
    }

    private let db: SQLiteDatabase

    init(path: String) throws {
        db = try SQLiteDatabase(path: path, readOnly: true)
    }

    /// nil when there is no catalog yet — a normal state (phase 5 downloads
    /// one); the UI degrades to manual entry, never crashes.
    static func openDefault() -> FoodCatalog? {
        guard FileManager.default.fileExists(atPath: defaultURL.path) else {
            return nil
        }
        return try? FoodCatalog(path: defaultURL.path)
    }

    /// One quoted prefix term per token, implicit AND between them —
    /// suivinut's `_fts_query`. Tokens are runs of letters, digits or
    /// underscore, so the quotes can never be escaped by the input.
    static func ftsQuery(for text: String) -> String? {
        let tokens = text.split { character in
            !(character.isLetter || character.isNumber || character == "_")
        }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    func search(_ query: String, limit: Int = 50) throws -> [Product] {
        guard let match = Self.ftsQuery(for: query) else { return [] }
        let rows = try db.rows(
            """
            SELECT p.* FROM products_fts f JOIN products p ON p.code = f.code
            WHERE products_fts MATCH ? ORDER BY rank LIMIT ?
            """,
            bindings: [.text(match), .integer(Int64(limit))]
        )
        return rows.map { row in
            Product(
                code: row["code"]?.stringValue ?? "",
                name: row["name"]?.stringValue ?? "",
                brands: row["brands"]?.stringValue ?? "",
                kcal100: row["kcal_100g"]?.doubleValue ?? 0,
                protein100: row["protein_100g"]?.doubleValue ?? 0,
                // NULL in the catalog (incomplete product): 0 is the honest
                // journal value — the entry stores what we know.
                carbs100: row["carbs_100g"]?.doubleValue ?? 0,
                fat100: row["fat_100g"]?.doubleValue ?? 0,
                servingSize: row["serving_size"]?.stringValue
            )
        }
    }
}
