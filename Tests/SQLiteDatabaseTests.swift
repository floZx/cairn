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
}
