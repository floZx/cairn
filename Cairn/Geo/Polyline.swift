/// Google Encoded Polyline Algorithm Format, precision 5 — the format Strava
/// uses for `map.summary_polyline`.
enum Polyline {
    static func decode(_ encoded: String) -> [Coordinate] {
        var coordinates: [Coordinate] = []
        var index = encoded.startIndex
        var lat = 0
        var lon = 0

        while index < encoded.endIndex {
            guard let dLat = nextValue(in: encoded, from: &index) else { break }
            guard let dLon = nextValue(in: encoded, from: &index) else { break }
            lat += dLat
            lon += dLon
            coordinates.append(
                Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5)
            )
        }
        return coordinates
    }

    static func encode(_ coordinates: [Coordinate]) -> String {
        var output = ""
        var previousLat = 0
        var previousLon = 0

        for coordinate in coordinates {
            let lat = Int((coordinate.latitude * 1e5).rounded())
            let lon = Int((coordinate.longitude * 1e5).rounded())
            append(lat - previousLat, to: &output)
            append(lon - previousLon, to: &output)
            previousLat = lat
            previousLon = lon
        }
        return output
    }

    /// Reads one varint-style chunk sequence. Returns nil on truncated input.
    private static func nextValue(
        in encoded: String, from index: inout String.Index
    ) -> Int? {
        var result = 0
        var shift = 0
        var byte = 0

        repeat {
            guard index < encoded.endIndex else { return nil }
            guard let ascii = encoded[index].asciiValue else { return nil }
            byte = Int(ascii) - 63
            index = encoded.index(after: index)
            result |= (byte & 0x1F) << shift
            shift += 5
        } while byte >= 0x20

        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }

    private static func append(_ value: Int, to output: inout String) {
        var zigzag = value < 0 ? ~(value << 1) : (value << 1)
        while zigzag >= 0x20 {
            output.append(Character(UnicodeScalar(UInt8((0x20 | (zigzag & 0x1F)) + 63))))
            zigzag >>= 5
        }
        output.append(Character(UnicodeScalar(UInt8(zigzag + 63))))
    }
}
