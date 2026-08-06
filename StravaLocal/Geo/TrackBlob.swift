import Foundation

/// Packs stream arrays into headerless little-endian binary blobs.
///
/// Streams are never queried, only read whole, so a compact packed
/// representation beats both JSON and a per-point table. The element type is
/// implied by the property holding the blob, which is why no header is needed.
enum TrackBlob {
    static func encode(coordinates: [Coordinate]) -> Data {
        var flat = [Double]()
        flat.reserveCapacity(coordinates.count * 2)
        for coordinate in coordinates {
            flat.append(coordinate.latitude)
            flat.append(coordinate.longitude)
        }
        return pack(flat)
    }

    static func decodeCoordinates(_ data: Data) -> [Coordinate] {
        let flat: [Double] = unpack(data)
        var coordinates = [Coordinate]()
        coordinates.reserveCapacity(flat.count / 2)
        var index = 0
        while index + 1 < flat.count {
            coordinates.append(
                Coordinate(latitude: flat[index], longitude: flat[index + 1])
            )
            index += 2
        }
        return coordinates
    }

    static func encode(scalars: [Float]) -> Data { pack(scalars) }
    static func decodeScalars(_ data: Data) -> [Float] { unpack(data) }
    static func encode(times: [Int32]) -> Data { pack(times) }
    static func decodeTimes(_ data: Data) -> [Int32] { unpack(data) }

    private static func pack<T>(_ values: [T]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Trailing bytes that don't form a whole element are dropped rather than
    /// trapping, so a corrupted store degrades instead of crashing.
    ///
    /// Reads are unaligned on purpose: `Data.withUnsafeBytes` makes no
    /// alignment promise, and a `Data` that is a slice of a larger buffer can
    /// start at any byte offset.
    private static func unpack<T>(_ data: Data) -> [T] {
        let stride = MemoryLayout<T>.stride
        let count = data.count / stride
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { raw in
            (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * stride, as: T.self) }
        }
    }
}
