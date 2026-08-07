import Foundation

/// Picks the part of a set of tracks worth showing first.
///
/// Framing every track means a single holiday ride abroad zooms the map out to
/// a continent, and the place the user actually trains becomes a smudge. So the
/// points are bucketed into a coarse grid, the busiest cell wins, and the
/// region covers that cell plus its immediate neighbours.
///
/// A median centre would be simpler but wrong for anyone who rides in two
/// cities: the median of two clusters lands in a field between them.
enum TrackDensity {
    /// Roughly 11 km of latitude — coarse enough that one ride's points don't
    /// each land in their own cell, fine enough to separate two towns.
    static let defaultCellDegrees = 0.1
    /// Cells kept on each side of the busiest one, so a region that spills over
    /// a cell edge is not cut in half.
    static let defaultNeighbourhood = 2
    /// Never return a region narrower than this, so one short track doesn't
    /// open the map at street level.
    static let minimumSpanDegrees = 0.02

    static func focusRegion(
        for tracks: [[Coordinate]],
        cellDegrees: Double = defaultCellDegrees,
        neighbourhood: Int = defaultNeighbourhood
    ) -> BoundingBox? {
        precondition(cellDegrees > 0, "cell size must be positive")

        var counts: [Cell: Int] = [:]
        for track in tracks {
            for point in track {
                counts[Cell(point, cellDegrees), default: 0] += 1
            }
        }

        // Ties broken on the cell's own coordinates: dictionary order is not
        // stable across runs, and the framing must not be either.
        guard let busiest = counts
            .max(by: { ($0.value, $0.key.x, $0.key.y) < ($1.value, $1.key.x, $1.key.y) })?
            .key
        else { return nil }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for track in tracks {
            for point in track {
                let cell = Cell(point, cellDegrees)
                guard abs(cell.x - busiest.x) <= neighbourhood,
                      abs(cell.y - busiest.y) <= neighbourhood
                else { continue }
                minLat = min(minLat, point.latitude)
                maxLat = max(maxLat, point.latitude)
                minLon = min(minLon, point.longitude)
                maxLon = max(maxLon, point.longitude)
            }
        }

        guard minLat <= maxLat else { return nil }

        let latPadding = max(0, minimumSpanDegrees - (maxLat - minLat)) / 2
        let lonPadding = max(0, minimumSpanDegrees - (maxLon - minLon)) / 2

        return BoundingBox(
            minLat: minLat - latPadding,
            maxLat: maxLat + latPadding,
            minLon: minLon - lonPadding,
            maxLon: maxLon + lonPadding
        )
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int

        init(_ coordinate: Coordinate, _ size: Double) {
            x = Int((coordinate.longitude / size).rounded(.down))
            y = Int((coordinate.latitude / size).rounded(.down))
        }
    }
}
