import Foundation

/// A value a mirrored row can hold. Explicit rather than `Any`, because the
/// rows are built in code and `JSONSerialization` on `Any` would let a wrong
/// type through to a 400 from PostgREST rather than to a compiler error.
enum MirrorValue: Sendable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case stringArray([String])
    case null

    /// The `JSONSerialization`-compatible form. A `Date` becomes an ISO 8601
    /// string with fractional seconds; a `Data` becomes Postgres' own
    /// hexadecimal literal for `bytea`, `\x` followed by two lowercase digits
    /// per byte.
    ///
    /// Hexadecimal and not base64, which an earlier version sent: PostgREST
    /// inserts through `json_populate_recordset`, so the string lands in
    /// `byteain`, which understands exactly two input formats — the `\x`
    /// hexadecimal one and the older "escape" one. A base64 string contains no
    /// backslash, so it is not rejected: it is read as *escape* format and
    /// stored as the ASCII bytes of the base64 text itself. No error, just a
    /// column holding the wrong bytes — the silence is what makes it worth
    /// spelling out here. `\x` is also the format PostgREST *returns* on a
    /// read, so the round trip is symmetric.
    var jsonValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        // NaN and infinity make `JSONSerialization` throw an Objective-C
        // exception Swift cannot catch — a crash, not an error. A pace or an
        // average speed is a division, so a non-finite result is not
        // theoretical; it becomes SQL NULL instead of taking the app down.
        case .double(let value): value.isFinite ? value : NSNull()
        case .bool(let value): value
        case .date(let value): MirrorValue.iso8601.string(from: value)
        case .data(let value): Self.postgresHex(value)
        case .stringArray(let values): values
        case .null: NSNull()
        }
    }

    /// `\x` followed by the bytes in hexadecimal — Postgres' `bytea` input
    /// format. Built by table lookup rather than `String(format: "%02x")` per
    /// byte: `activity.simplified_track` runs to a few thousand bytes and the
    /// formatter costs a full format-string parse for each one of them.
    private static func postgresHex(_ data: Data) -> String {
        let digits: [Character] = [
            "0", "1", "2", "3", "4", "5", "6", "7",
            "8", "9", "a", "b", "c", "d", "e", "f",
        ]
        var hex = "\\x"
        hex.reserveCapacity(2 + data.count * 2)
        for byte in data {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0F)])
        }
        return hex
    }

    /// The wire format for a date, and the one this file's `.date` case
    /// writes. It lives with the value it serialises rather than with the
    /// client that posts it: `cairn-note` builds mirror rows without ever
    /// opening a socket.
    ///
    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` is not `Sendable`,
    /// but this instance is only ever read, never mutated after creation —
    /// the same justification `GPXWriter` uses for its own formatter.
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
