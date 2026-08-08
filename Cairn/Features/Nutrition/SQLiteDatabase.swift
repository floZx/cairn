// Cairn/Features/Nutrition/SQLiteDatabase.swift
import Foundation
import SQLite3

/// The thinnest possible wrapper over the system SQLite: open, run, read
/// rows. It exists for the one-shot suivinut import and, later, the OFF
/// catalog — SwiftData owns everything else, so this deliberately has no
/// bindings, no statement cache, no migration story.
final class SQLiteDatabase {
    enum Value: Equatable {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null

        var int64Value: Int64? {
            if case let .integer(value) = self { return value }
            return nil
        }

        var intValue: Int? { int64Value.map(Int.init) }

        /// Integers coerce to double — SQLite columns are dynamically typed
        /// and a REAL column happily stores `80` as an integer.
        var doubleValue: Double? {
            switch self {
            case let .real(value): return value
            case let .integer(value): return Double(value)
            default: return nil
            }
        }

        var stringValue: String? {
            if case let .text(value) = self { return value }
            return nil
        }
    }

    struct Error: Swift.Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private var handle: OpaquePointer?

    init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "impossible d'ouvrir la base"
            sqlite3_close(handle)
            handle = nil
            throw Error(message: message)
        }
    }

    deinit { sqlite3_close(handle) }

    /// Statements that return nothing — DDL, INSERT. Several statements
    /// separated by `;` are fine, `sqlite3_exec` runs the batch.
    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK
        else {
            let message = errorPointer.map { String(cString: $0) }
                ?? "échec d'exécution"
            sqlite3_free(errorPointer)
            throw Error(message: message)
        }
    }

    /// All rows of a SELECT, keyed by column name. Materialising the whole
    /// result is fine for the volumes this reads — hundreds of journal rows;
    /// the catalog build in phase 5 will stream on its own terms.
    func rows(_ sql: String) throws -> [[String: Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK
        else {
            throw Error(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String: Value]] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            var row: [String: Value] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = value(of: statement, at: index)
            }
            result.append(row)
            stepResult = sqlite3_step(statement)
        }
        // The loop only exits on a non-ROW result; SQLITE_DONE is the only
        // one meaning "all rows read". Anything else (SQLITE_CORRUPT,
        // SQLITE_IOERR, SQLITE_BUSY, SQLITE_ERROR…) is a mid-query failure —
        // without this check it would silently return a truncated result.
        guard stepResult == SQLITE_DONE else {
            throw Error(message: String(cString: sqlite3_errmsg(handle)))
        }
        return result
    }

    private func value(of statement: OpaquePointer?, at index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(statement, index)))
        default:
            return .null
        }
    }
}
