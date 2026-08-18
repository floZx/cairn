// Cairn/Features/Nutrition/CatalogBuilder.swift
import Foundation

/// Builds `off.db` from the gzipped Open Food Facts CSV export: gunzip
/// streams into a line parser, filtered rows land in `<offDBPath>.tmp` in
/// batched transactions, FTS is built once at the end, and the finished
/// file atomically replaces the current catalog — a failure anywhere leaves
/// the existing catalog untouched.
enum CatalogBuilder {
    static let catalogURL = URL(
        string: "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
    )!

    struct BuildError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// One transaction per batch: per-row commits made a million-row build
    /// crawl; a single giant transaction holds the page cache hostage.
    private static let batchSize = 5_000

    static func build(
        gzPath: String, offDBPath: String, importedAt: String,
        onProgress: (@Sendable (_ linesSeen: Int, _ kept: Int) -> Void)? = nil
    ) throws -> Int {
        let tmpPath = offDBPath + ".tmp"
        let journalPath = tmpPath + "-journal"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: tmpPath) {
            try fileManager.removeItem(atPath: tmpPath)
        }
        try? fileManager.removeItem(atPath: journalPath)

        let gunzip = Process()
        gunzip.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        gunzip.arguments = ["-c", gzPath]
        let stdout = Pipe()
        gunzip.standardOutput = stdout
        // gunzip may spew warnings on a corrupt stream; nobody reads them,
        // and an undrained pipe fills up and blocks gunzip's write — which
        // would stall stdout and hang consume() past cancellation. Send it
        // to the bit bucket; the exit code is the diagnostic.
        gunzip.standardError = FileHandle.nullDevice
        try gunzip.run()

        do {
            let count = try consume(
                stdout.fileHandleForReading, into: tmpPath,
                importedAt: importedAt, onProgress: onProgress
            )
            gunzip.waitUntilExit()
            guard gunzip.terminationStatus == 0 else {
                throw BuildError(
                    message: "gunzip a échoué (code \(gunzip.terminationStatus)) — "
                        + "le fichier téléchargé est probablement corrompu."
                )
            }
            // The atomic hand-over: everything before this line only ever
            // touched the .tmp file.
            if fileManager.fileExists(atPath: offDBPath) {
                _ = try fileManager.replaceItemAt(
                    URL(fileURLWithPath: offDBPath),
                    withItemAt: URL(fileURLWithPath: tmpPath)
                )
            } else {
                try fileManager.moveItem(atPath: tmpPath, toPath: offDBPath)
            }
            return count
        } catch {
            gunzip.terminate()
            gunzip.waitUntilExit()
            try? fileManager.removeItem(atPath: tmpPath)
            try? fileManager.removeItem(atPath: journalPath)
            // A corrupt .gz makes gunzip exit non-zero with empty stdout
            // before writing a single line — `consume` never sees a header
            // and throws its own "Export vide" error first, which reaches
            // here before the success path's termination-status guard ever
            // runs. Surface the real diagnostic (gunzip's exit code) instead
            // of the misleading "empty export" one. Gated on
            // `terminationReason == .exit`: our own `terminate()` just above
            // kills a gunzip that was still mid-stream when some *other*
            // error (e.g. cancellation) interrupted `consume` — that reports
            // `.uncaughtSignal`, not `.exit`, so genuine cancellation/DB
            // errors still propagate as themselves instead of being
            // relabelled "corrompu".
            if gunzip.terminationReason == .exit, gunzip.terminationStatus != 0 {
                throw BuildError(
                    message: "gunzip a échoué (code \(gunzip.terminationStatus)) — "
                        + "le fichier téléchargé est probablement corrompu."
                )
            }
            throw error
        }
    }

    private static func consume(
        _ output: FileHandle, into tmpPath: String, importedAt: String,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) throws -> Int {
        let db = try SQLiteDatabase(path: tmpPath)
        // The .tmp is disposable and the atomic swap is the integrity
        // boundary: a crash mid-build means a rebuild, never a corrupt live
        // catalog. So the durability machinery is pure overhead here — no
        // journal, no fsync, and a page cache big enough that random-order
        // primary-key inserts stop thrashing.
        try db.execute("PRAGMA journal_mode = OFF")
        try db.execute("PRAGMA synchronous = OFF")
        try db.execute("PRAGMA cache_size = -65536")
        try db.execute("""
            CREATE TABLE products (
                code TEXT PRIMARY KEY, name TEXT NOT NULL, brands TEXT,
                quantity TEXT, kcal_100g REAL NOT NULL,
                protein_100g REAL NOT NULL, carbs_100g REAL, fat_100g REAL,
                fiber_100g REAL,
                serving_size TEXT, completeness REAL);
            CREATE VIRTUAL TABLE products_fts USING fts5(
                name, brands, code UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2');
            CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        // One parse instead of one per row: the CSV export runs to
        // millions of lines, and `sqlite3_prepare_v2` per INSERT was a
        // measurable share of the build's cost.
        let insertStatement = try db.prepare(
            """
            INSERT OR REPLACE INTO products
                (code, name, brands, quantity, kcal_100g, protein_100g,
                 carbs_100g, fat_100g, fiber_100g, serving_size, completeness)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """
        )

        var columns: CatalogCSV.Columns?
        var remainder = Data()
        var linesSeen = 0
        var kept = 0
        var batchOpen = false

        func insert(_ row: CatalogCSV.Row) throws {
            if !batchOpen {
                try db.execute("BEGIN")
                batchOpen = true
            }
            try insertStatement.execute(bindings: [
                .text(row.code), .text(row.name),
                row.brands.map(SQLiteDatabase.Value.text) ?? .null,
                row.quantity.map(SQLiteDatabase.Value.text) ?? .null,
                .real(row.kcal), .real(row.protein),
                row.carbs.map(SQLiteDatabase.Value.real) ?? .null,
                row.fat.map(SQLiteDatabase.Value.real) ?? .null,
                row.fiber.map(SQLiteDatabase.Value.real) ?? .null,
                row.servingSize.map(SQLiteDatabase.Value.text) ?? .null,
                .real(row.completeness),
            ])
            kept += 1
            if kept % batchSize == 0 {
                try db.execute("COMMIT")
                batchOpen = false
                try Task.checkCancellation()
                onProgress?(linesSeen, kept)
            }
        }

        func process(lineData: Data) throws {
            guard !lineData.isEmpty else { return }
            let line = String(decoding: lineData, as: UTF8.self)
            if let columns {
                linesSeen += 1
                if let row = CatalogCSV.row(from: line, columns: columns) {
                    try insert(row)
                }
                if linesSeen % 50_000 == 0 {
                    try Task.checkCancellation()
                    onProgress?(linesSeen, kept)
                }
            } else {
                columns = try CatalogCSV.columns(from: line)
            }
        }

        while true {
            let chunk = output.availableData
            if chunk.isEmpty { break }
            remainder.append(chunk)
            while let newline = remainder.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = remainder.subdata(
                    in: remainder.startIndex..<newline)
                remainder.removeSubrange(remainder.startIndex...newline)
                try process(lineData: lineData)
            }
        }
        if !remainder.isEmpty {
            try process(lineData: remainder)
        }
        guard columns != nil else {
            throw BuildError(message: "Export vide — aucune ligne d'en-tête.")
        }

        if batchOpen { try db.execute("COMMIT") }
        // The FTS rebuild is one multi-second statement: the last chance to
        // honour « Annuler » is right before it.
        try Task.checkCancellation()
        try db.execute(
            "INSERT INTO products_fts(name, brands, code) "
            + "SELECT name, COALESCE(brands, ''), code FROM products"
        )
        _ = try db.rows(
            "INSERT INTO catalog_meta(key, value) VALUES ('imported_at', ?)",
            bindings: [.text(importedAt)]
        )
        _ = try db.rows(
            "INSERT INTO catalog_meta(key, value) VALUES ('threshold', ?)",
            bindings: [.text(String(CatalogCSV.completenessThreshold))]
        )
        onProgress?(linesSeen, kept)
        let count = try db.rows("SELECT COUNT(*) AS n FROM products")
            .first?["n"]?.intValue ?? 0
        return count
    }
}
