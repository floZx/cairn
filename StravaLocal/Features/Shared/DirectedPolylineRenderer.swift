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

    /// On-screen size, in points, kept deliberately close to the 3-point track:
    /// a chevron much wider than the line it sits on reads as a blob rather than
    /// an arrow, which is what a first version at more than twice this did.
    private static let chevronLength: CGFloat = 6
    private static let chevronStroke: CGFloat = 1.4

    /// Black or white, whichever actually contrasts more with the track.
    ///
    /// Not "is the track light or dark", which is the question a first version
    /// asked with a threshold picked by eye at 0.55. A saturated red sits at a
    /// relative luminance near 0.25 and so counted as dark, keeping the chevrons
    /// white on the very colour where they disappeared. Worse, the test that was
    /// meant to catch it used orange, which happened to land the other side of
    /// that threshold — it confirmed the assumption instead of checking the
    /// requirement.
    ///
    /// The crossover is not a matter of taste. WCAG contrast against white is
    /// `1.05 / (L + 0.05)` and against black `(L + 0.05) / 0.05`; they cross at
    /// `L ≈ 0.179`. Above it black wins, below it white does. Which means black on
    /// nearly every track colour, and white only on the genuinely dark ones —
    /// black being one of the options, that case is real.
    static func chevronColor(on stroke: NSColor) -> NSColor {
        relativeLuminance(of: stroke) > 0.179 ? .black : .white
    }

    /// WCAG relative luminance, gamma-decoded.
    ///
    /// Converts before reading, and that is not defensive padding: `NSColor.black`
    /// lives in Generic Gray, where `redComponent` raises rather than returning
    /// zero. Black is one of the track colours on offer, so an API that trapped on
    /// it would be a loaded gun.
    ///
    /// The gamma decoding matters too. On raw sRGB components a mid-tone reads far
    /// brighter than the eye finds it, and that is part of how red ended up on the
    /// wrong side of the crossover.
    static func relativeLuminance(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

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

        // Divided by the zoom scale, which is what turns a size in screen points
        // into this context's units — the same conversion MapKit applies to
        // `lineWidth`. So a chevron stays six points wide at every zoom.
        let size = Self.chevronLength / zoomScale
        // Widened by one chevron so a mark straddling the tile edge is drawn by
        // both tiles rather than sliced in half by whichever gets there first.
        let margin = Double(size)
        let visible = mapRect.insetBy(dx: -margin, dy: -margin)

        let colour = Self.chevronColor(on: strokeColor ?? .controlAccentColor)
        context.setStrokeColor(colour.cgColor)
        context.setLineWidth(Self.chevronStroke / zoomScale)
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
