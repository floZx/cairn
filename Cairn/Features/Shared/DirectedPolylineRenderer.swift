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

/// A track drawn with arrowheads showing which way it was travelled.
///
/// Drawn inside the renderer rather than as annotation views: an
/// `MKAnnotationView` keeps its orientation when the map is rotated, so its
/// arrows would point the wrong way the moment the user turns the map. Here
/// MapKit's own transform handles rotation and pitch.
///
/// Modelled on how Strava draws the same thing, after two versions of mine were
/// rightly called ugly. The arrowheads are *filled and in the track's own colour*,
/// a little wider than the line: what makes them legible is the silhouette
/// against the map, not a contrasting colour against the line. A first version
/// stroked them in black or white, which read as debris scattered along the route.
/// And there are four of them, not fourteen — the point is to answer "which way",
/// which four do as well as forty and without crowding the trace.
final class DirectedPolylineRenderer: MKPolylineRenderer {
    private static let arrowCount = 4

    /// On-screen points, and the ratio to the line is what matters: the arrowhead
    /// spans about three times the 2-point stroke, as Strava's does. At twice the
    /// width it read as a bulge in the line rather than a barb, which is why the
    /// same-colour version came out too discreet to see.
    private static let arrowLength: CGFloat = 9
    private static let arrowHalfWidth: CGFloat = 3.5

    private lazy var markers: [DirectionMarker] = {
        let line = polyline
        let buffer = UnsafeBufferPointer(start: line.points(), count: line.pointCount)
        return TrackDirection.markers(along: Array(buffer), count: Self.arrowCount)
    }()

    override func draw(
        _ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext
    ) {
        super.draw(mapRect, zoomScale: zoomScale, in: context)

        // Divided by the zoom scale, which is what turns a size in screen points
        // into this context's units — the same conversion MapKit applies to
        // `lineWidth`. So an arrowhead keeps its size at every zoom.
        let length = Self.arrowLength / zoomScale
        let halfWidth = Self.arrowHalfWidth / zoomScale
        // Widened by one arrowhead so a mark straddling the tile edge is drawn by
        // both tiles rather than sliced in half by whichever gets there first.
        let visible = mapRect.insetBy(dx: -Double(length), dy: -Double(length))

        context.setFillColor((strokeColor ?? .controlAccentColor).cgColor)

        for marker in markers where visible.contains(marker.point) {
            let origin = point(for: marker.point)
            context.saveGState()
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: marker.angle)
            // A solid barb pointing along the direction of travel, its base set
            // back over the line so the tip is what stands out.
            context.move(to: CGPoint(x: length * 0.5, y: 0))
            context.addLine(to: CGPoint(x: -length * 0.35, y: -halfWidth))
            context.addLine(to: CGPoint(x: -length * 0.35, y: halfWidth))
            context.closePath()
            context.fillPath()
            context.restoreGState()
        }
    }
}
