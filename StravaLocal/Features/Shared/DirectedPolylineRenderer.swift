import MapKit

/// A spot along a track and the direction of travel there.
///
/// Not `Equatable`: `MKMapPoint` is a C struct with no conformance, and comparing
/// two floating-point positions for equality would be the wrong test anyway.
struct DirectionMarker {
    let point: MKMapPoint
    /// Radians, in map space. Angles survive the conversion to renderer
    /// coordinates because that is a uniform scale and translation.
    let angle: CGFloat
}

/// Where to put the direction chevrons along a track.
///
/// Separate from the drawing so the geometry can be tested: which way a route is
/// travelled is the whole point of the feature, and getting it backwards would be
/// worse than showing nothing.
enum TrackDirection {
    /// Evenly spaced by distance travelled, not by index.
    ///
    /// A track's points are unevenly spaced — dense in the switchbacks, sparse on
    /// a straight — so every nth point would cluster the chevrons exactly where
    /// the route is already hard to read.
    static func markers(along points: [MKMapPoint], count: Int) -> [DirectionMarker] {
        guard count > 0, points.count > 1 else { return [] }

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(points.count)
        for index in 1..<points.count {
            cumulative.append(
                cumulative[index - 1] + points[index].distance(to: points[index - 1])
            )
        }
        guard let total = cumulative.last, total > 0 else { return [] }

        // Offset by half a step so no chevron sits on the start marker or runs
        // off the end of the line.
        let step = total / Double(count)
        return (0..<count).compactMap { slot in
            let target = step * (Double(slot) + 0.5)
            guard let index = cumulative.firstIndex(where: { $0 >= target }),
                  index > 0 else { return nil }

            let previous = points[index - 1]
            let next = points[index]
            // Interpolated between the two surrounding points rather than snapped
            // to one: on a long straight the nearest point can be far away.
            let span = cumulative[index] - cumulative[index - 1]
            let ratio = span > 0 ? (target - cumulative[index - 1]) / span : 0
            let position = MKMapPoint(
                x: previous.x + (next.x - previous.x) * ratio,
                y: previous.y + (next.y - previous.y) * ratio
            )
            return DirectionMarker(
                point: position,
                angle: atan2(CGFloat(next.y - previous.y), CGFloat(next.x - previous.x))
            )
        }
    }
}

/// A track drawn with chevrons showing which way it was travelled.
///
/// Chevrons rather than annotation views: an `MKAnnotationView` keeps its
/// orientation when the map is rotated, so its arrows would end up pointing the
/// wrong way the moment the user turns the map. Drawing inside the renderer means
/// MapKit's own transform handles rotation and pitch.
final class DirectedPolylineRenderer: MKPolylineRenderer {
    /// Fixed along the whole route, so a zoomed-out view shows them all. Zoom far
    /// enough in and you may sit between two, which is the acceptable half of the
    /// trade: spacing them by screen distance instead would make them shuffle
    /// along the track at every zoom.
    private static let chevronCount = 14

    private lazy var markers: [DirectionMarker] = {
        let line = polyline
        let buffer = UnsafeBufferPointer(start: line.points(), count: line.pointCount)
        return TrackDirection.markers(
            along: Array(buffer), count: Self.chevronCount
        )
    }()

    override func draw(
        _ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext
    ) {
        super.draw(mapRect, zoomScale: zoomScale, in: context)

        // Scaled off MapKit's own road width so the chevrons keep their apparent
        // size at every zoom, as the line does.
        let size = max(7, MKRoadWidthAtZoomScale(zoomScale) * 2.2)
        // Widened by one chevron so a mark straddling the tile edge is drawn by
        // both tiles rather than sliced in half by whichever gets there first.
        let margin = Double(size) / Double(zoomScale)
        let visible = mapRect.insetBy(dx: -margin, dy: -margin)

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(max(1, size * 0.2))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for marker in markers where visible.contains(marker.point) {
            let origin = point(for: marker.point)
            context.saveGState()
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: marker.angle)
            // A "greater than" sign pointing along the direction of travel.
            context.move(to: CGPoint(x: -size * 0.45, y: -size * 0.4))
            context.addLine(to: CGPoint(x: size * 0.45, y: 0))
            context.addLine(to: CGPoint(x: -size * 0.45, y: size * 0.4))
            context.strokePath()
            context.restoreGState()
        }
    }
}
