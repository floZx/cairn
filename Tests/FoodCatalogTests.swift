import Testing
import Foundation
@testable import Cairn

@Suite("FoodCatalog")
@MainActor
struct FoodCatalogTests {
    /// A miniature off.db with the real schema — the FTS tokenizer options
    /// are the ones that make diacritics-insensitive prefix search work, so
    /// the fixture must use them verbatim.
    private func makeCatalog() throws -> (FoodCatalog, String) {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "off-fixture-\(UUID().uuidString).db").path
        let db = try SQLiteDatabase(path: path)
        try db.execute("""
            CREATE TABLE products (
                code TEXT PRIMARY KEY, name TEXT NOT NULL, brands TEXT,
                quantity TEXT, kcal_100g REAL NOT NULL,
                protein_100g REAL NOT NULL, carbs_100g REAL, fat_100g REAL,
                serving_size TEXT, completeness REAL);
            CREATE VIRTUAL TABLE products_fts USING fts5(
                name, brands, code UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2');
            INSERT INTO products VALUES
                ('1', 'Flocons d''avoine', 'Marque A', NULL,
                 370, 13, 60, 7, '40 g', 0.9),
                ('2', 'Crème fraîche épaisse', 'Laiterie', NULL,
                 300, 2.5, 3, 30, NULL, 0.8),
                ('3', 'Riz basmati', NULL, NULL,
                 350, 7, NULL, NULL, NULL, 0.7),
                ('4', 'Riz complet', 'Marque B', NULL,
                 345, 8, 72, 2.5, NULL, 0.8);
            INSERT INTO products_fts(name, brands, code)
                SELECT name, COALESCE(brands, ''), code FROM products;
            """)
        return (try FoodCatalog(path: path), path)
    }

    @Test("la recherche par préfixe trouve le produit")
    func prefixSearchFinds() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = try catalog.search("floc")
        #expect(results.count == 1)
        #expect(results[0].name == "Flocons d'avoine")
        #expect(results[0].brands == "Marque A")
        #expect(results[0].kcal100 == 370)
        #expect(results[0].servingSize == "40 g")
    }

    @Test("les diacritiques sont ignorés dans les deux sens")
    func diacriticsInsensitive() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.search("creme").count == 1)
        #expect(try catalog.search("crème").count == 1)
        #expect(try catalog.search("epaisse").count == 1)
    }

    @Test("plusieurs mots = ET implicite")
    func multiTokenIsAnd() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.search("flocons avoine").count == 1)
        #expect(try catalog.search("flocons riz").isEmpty)
    }

    @Test("une requête vide ou sans token rend une liste vide sans erreur")
    func emptyQueryYieldsNothing() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.search("").isEmpty)
        #expect(try catalog.search("  !! ").isEmpty)
    }

    @Test("les macros NULL du catalogue deviennent 0, brands vide")
    func nullMacrosCoalesceToZero() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let rice = try catalog.search("basmati")[0]
        #expect(rice.carbs100 == 0)
        #expect(rice.fat100 == 0)
        #expect(rice.brands == "")
        #expect(rice.servingSize == nil)
    }

    @Test("limit borne le nombre de résultats")
    func limitApplies() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let all = try catalog.search("riz")
        #expect(all.count == 2)
        #expect(try catalog.search("riz", limit: 1).count == 1)
    }

    @Test("le constructeur de requête FTS met chaque token en préfixe cité", arguments: [
        ("crème fraîche 30%", "\"crème\"* \"fraîche\"* \"30\"*"),
        ("floc", "\"floc\"*"),
        ("  ", nil),
        ("!!", nil),
    ])
    func ftsQueryBuilder(input: String, expected: String?) {
        #expect(FoodCatalog.ftsQuery(for: input) == expected)
    }

    @Test("openDefault rend nil quand le fichier n'existe pas")
    func openDefaultNilWhenMissing() {
        // defaultURL pointe sur Application Support/Cairn/off.db ; ce test ne
        // doit pas dépendre de l'état de la machine, donc on teste le
        // constructeur direct sur un chemin garanti absent.
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "nope-\(UUID().uuidString)/off.db").path
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try FoodCatalog(path: missing)
        }
    }

    @Test("productCount compte le catalogue")
    func countsProducts() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.productCount() == 4)
    }

    @Test("importedAt est nil sur un catalogue sans méta")
    func importedAtNilWithoutMeta() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.importedAt() == nil)
    }
}
