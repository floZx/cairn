import MapKit

/// Where a track begins.
///
/// A distinct class rather than a plain `MKPointAnnotation` because the activity
/// map also carries the hover marker that follows the cursor over the charts: the
/// delegate is handed only the annotation, so the two have to be tellable apart
/// or one of them gets the other's look.
final class StartAnnotation: MKPointAnnotation {
    /// Matches the track it belongs to, which is what makes the comparison map
    /// readable — several starts on screen at once, each on its own route.
    var color: NSColor = .controlAccentColor
}

/// The hover marker on the activity map, sliding along the track as the cursor
/// crosses a chart. Named for the same reason as `StartAnnotation`.
final class HoverAnnotation: MKPointAnnotation {}

extension MKMapView {
    /// The view for a start marker, or nil if this is not one.
    ///
    /// A ring rather than a pin: a pin's tip claims a precise spot and covers the
    /// first metres of the very track it is marking, which on a loop is also the
    /// last.
    func startAnnotationView(for annotation: any MKAnnotation) -> MKAnnotationView? {
        guard let start = annotation as? StartAnnotation else { return nil }

        let identifier = "start"
        let view = dequeueReusableAnnotationView(withIdentifier: identifier)
            ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.canShowCallout = false
        view.isEnabled = false
        // Rebuilt rather than cached: the colour is per activity, and a reused
        // view would otherwise keep the previous track's.
        view.image = Self.startImage(color: start.color)
        return view
    }

    private static func startImage(color: NSColor) -> NSImage {
        let diameter: CGFloat = 15
        let image = NSImage(
            size: NSSize(width: diameter, height: diameter), flipped: false
        ) { rect in
            // White outer ring so the marker holds up over a dark satellite tile
            // as well as a pale topographic one.
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 5.5, dy: 5.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
