import MapKit

/// A group of tracks sharing one stroke colour.
///
/// `MKMultiPolylineRenderer` carries a single colour for everything it draws, so
/// alternating colours means grouping the tracks by colour rather than giving each
/// its own overlay — eight overlays instead of hundreds.
final class ColoredMultiPolyline: MKMultiPolyline {
    var color: NSColor = .controlAccentColor
}

/// Finds which track a click landed on.
///
/// MapKit hit-tests annotations but not overlay renderers, so this is ours to do.
/// Pure geometry in map-point space, kept out of the view so it can be tested:
/// picking the wrong track would open the wrong activity, which is worse than
/// opening none.
enum TrackHitTest {
    /// The track closest to a point, if any lies within `tolerance` map points.
    ///
    /// Bounding boxes are checked before segments. With several hundred tracks on
    /// screen, comparing every segment of every one of them on each click is work
    /// that a rectangle test throws away almost all of — a click is nowhere near
    /// most routes.
    static func nearestTrack(
        to point: MKMapPoint, in tracks: [[MKMapPoint]], within tolerance: Double
    ) -> Int? {
        var best: (index: Int, distance: Double)?

        for (index, track) in tracks.enumerated() where track.count > 1 {
            guard let box = boundingRect(of: track),
                  box.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            else { continue }

            var closest = Double.greatestFiniteMagnitude
            for segment in 1..<track.count {
                closest = min(
                    closest,
                    distance(from: point, to: track[segment - 1], track[segment])
                )
                // Nothing nearer than zero, and a long track can stop early.
                if closest == 0 { break }
            }
            guard closest <= tolerance else { continue }
            if best == nil || closest < best!.distance {
                best = (index, closest)
            }
        }
        return best?.index
    }

    /// Distance from a point to a segment, not to its endpoints.
    ///
    /// Endpoint distance would miss a click in the middle of a long straight,
    /// which on a simplified track is most of its length.
    static func distance(
        from point: MKMapPoint, to start: MKMapPoint, _ end: MKMapPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        // hypot, not `MKMapPoint.distance(to:)`: that one answers in metres while
        // everything here works in map points, and the tolerance is derived from
        // the visible rect. Mixing the two would make the hit area depend on
        // latitude.
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        // Where the perpendicular meets the line, clamped to the segment.
        let t = max(
            0,
            min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
        )
        let projection = MKMapPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private static func boundingRect(of track: [MKMapPoint]) -> MKMapRect? {
        guard let first = track.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in track.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return MKMapRect(
            x: minX, y: minY, width: maxX - minX, height: maxY - minY
        )
    }
}
