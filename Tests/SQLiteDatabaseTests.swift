// Tests/SQLiteDatabaseTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "sqlite-test-\(UUID().uuidString).db").path
    }

    @Test("créer, insérer, relire avec les bons types")
    func roundTripsTypedValues() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute("""
            CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, kcal REAL, code TEXT);
            INSERT INTO t (name, kcal, code) VALUES ('Riz', 350.5, NULL);
            """)
        let rows = try db.rows("SELECT id, name, kcal, code FROM t")
        #expect(rows.count == 1)
        #expect(rows[0]["id"] == .integer(1))
        #expect(rows[0]["name"] == .text("Riz"))
        #expect(rows[0]["kcal"] == .real(350.5))
        #expect(rows[0]["code"] == .null)
    }

    @Test("les accesseurs coercent les entiers en double, pas l'inverse")
    func valueAccessorsCoerce() {
        #expect(SQLiteDatabase.Value.integer(42).doubleValue == 42.0)
        #expect(SQLiteDatabase.Value.integer(42).intValue == 42)
        #expect(SQLiteDatabase.Value.real(1.5).doubleValue == 1.5)
        #expect(SQLiteDatabase.Value.real(1.5).intValue == nil)
        #expect(SQLiteDatabase.Value.text("x").stringValue == "x")
        #expect(SQLiteDatabase.Value.null.stringValue == nil)
    }

    @Test("l'ouverture en lecture seule d'un fichier absent échoue")
    func readOnlyOpenOfMissingFileThrows() {
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try SQLiteDatabase(path: temporaryPath(), readOnly: true)
        }
    }

    @Test("écrire sur une base ouverte en lecture seule échoue")
    func writeOnReadOnlyThrows() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try SQLiteDatabase(path: path)
        try writer.execute("CREATE TABLE t (id INTEGER)")
        let reader = try SQLiteDatabase(path: path, readOnly: true)
        #expect(throws: SQLiteDatabase.Error.self) {
            try reader.execute("INSERT INTO t VALUES (1)")
        }
    }

    @Test("une requête sur une table absente échoue proprement")
    func queryOnMissingTableThrows() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try db.rows("SELECT * FROM absente")
        }
    }

    @Test("une erreur en cours de lecture lève au lieu de tronquer silencieusement le résultat")
    func midReadFailureThrowsInsteadOfTruncating() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let writer = try SQLiteDatabase(path: path)
            // Enough padded rows to span many database pages: the schema
            // (page 1) stays intact after truncation below, but the scan has
            // to cross into the missing back half of the file before it can
            // reach SQLITE_DONE.
            var sql = "CREATE TABLE t (id INTEGER PRIMARY KEY, padding TEXT);\n"
            for _ in 0..<2000 {
                sql += "INSERT INTO t (padding) VALUES ('\(String(repeating: "x", count: 200))');\n"
            }
            try writer.execute(sql)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        let size = try handle.seekToEnd()
        try handle.truncate(atOffset: size / 2)
        try handle.close()

        let reader = try SQLiteDatabase(path: path, readOnly: true)
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try reader.rows("SELECT id, padding FROM t ORDER BY id")
        }
    }

    @Test("les bindings passent texte, entier, réel et null")
    func bindsAllValueKinds() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute(
            "CREATE TABLE t (name TEXT, kcal REAL, count INTEGER, note TEXT);"
            + "INSERT INTO t VALUES ('Riz', 350.0, 2, NULL);"
            + "INSERT INTO t VALUES ('Crème', 300.0, 5, 'x');"
        )
        let rows = try db.rows(
            "SELECT name FROM t WHERE kcal = ? AND count = ? AND name = ?",
            bindings: [.real(350.0), .integer(2), .text("Riz")]
        )
        #expect(rows.count == 1)
        #expect(rows[0]["name"] == .text("Riz"))
        let none = try db.rows(
            "SELECT name FROM t WHERE note IS NOT ?", bindings: [.null]
        )
        #expect(none.count == 1)
        #expect(none[0]["name"] == .text("Crème"))
    }

    @Test("un texte piégé reste une valeur, jamais du SQL")
    func bindingsAreNotInterpolated() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute(
            "CREATE TABLE t (name TEXT);"
            + "INSERT INTO t VALUES ('sain');"
        )
        let hostile = "'; DROP TABLE t; --"
        let rows = try db.rows(
            "SELECT name FROM t WHERE name = ?", bindings: [.text(hostile)]
        )
        #expect(rows.isEmpty)
        // La table doit avoir survécu au texte hostile.
        #expect(try db.rows("SELECT name FROM t").count == 1)
    }

    @Test("un nombre de bindings incohérent échoue proprement")
    func mismatchedBindingCountThrows() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE t (a TEXT)")
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try db.rows("SELECT a FROM t WHERE a = ?", bindings: [])
        }
        #expect(throws: SQLiteDatabase.Error.self) {
            _ = try db.rows(
                "SELECT a FROM t", bindings: [.text("de trop")]
            )
        }
    }

    @Test("une instruction préparée s'exécute plusieurs fois avec des bindings différents")
    func preparedStatementExecutesRepeatedly() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE t (name TEXT, kcal REAL)")
        let insert = try db.prepare("INSERT INTO t (name, kcal) VALUES (?, ?)")
        try insert.execute(bindings: [.text("Riz"), .real(350.0)])
        try insert.execute(bindings: [.text("Crème"), .real(300.0)])
        try insert.execute(bindings: [.text("Pain"), .real(265.0)])
        let rows = try db.rows("SELECT name, kcal FROM t ORDER BY kcal")
        #expect(rows.count == 3)
        #expect(rows[0]["name"] == .text("Pain"))
        #expect(rows[0]["kcal"] == .real(265.0))
        #expect(rows[1]["name"] == .text("Crème"))
        #expect(rows[2]["name"] == .text("Riz"))
    }

    @Test("un nombre de bindings incohérent sur une instruction préparée échoue")
    func preparedStatementMismatchedBindingCountThrows() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE t (name TEXT, kcal REAL)")
        let insert = try db.prepare("INSERT INTO t (name, kcal) VALUES (?, ?)")
        #expect(throws: SQLiteDatabase.Error.self) {
            try insert.execute(bindings: [.text("Riz")])
        }
    }

    @Test("après une erreur, l'instruction préparée redevient utilisable")
    func preparedStatementUsableAfterError() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        try db.execute("CREATE TABLE t (name TEXT UNIQUE, kcal REAL)")
        let insert = try db.prepare("INSERT INTO t (name, kcal) VALUES (?, ?)")
        try insert.execute(bindings: [.text("Riz"), .real(350.0)])
        #expect(throws: SQLiteDatabase.Error.self) {
            try insert.execute(bindings: [.text("Riz"), .real(999.0)])
        }
        // La même instruction, réinitialisée par le reset du defer, sert
        // encore pour la ligne suivante.
        try insert.execute(bindings: [.text("Pain"), .real(265.0)])
        let rows = try db.rows("SELECT name FROM t ORDER BY name")
        #expect(rows.count == 2)
        #expect(rows[0]["name"] == .text("Pain"))
        #expect(rows[1]["name"] == .text("Riz"))
    }
}
