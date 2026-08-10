import AppKit

/// Transparent layer above the map that captures a rubber-band drag.
///
/// Drawing the rectangle here rather than in MKMapView keeps map gestures and
/// selection gestures from fighting over the same drag: when disabled, the view
/// declines every hit test and the map behaves exactly as if it weren't there.
///
/// The cursor is not its business — `CursorAssertingMapView` owns that, and this
/// covering the map is precisely why: two views claiming a cursor over the same
/// pixels is how the resize double-arrow got to linger here and nowhere else.
final class SelectionOverlayView: NSView {
    var isEnabled = false {
        didSet {
            if !isEnabled { currentRect = nil }
            needsDisplay = true
        }
    }
    var onSelection: ((NSRect) -> Void)?

    private var anchor: NSPoint?
    private var currentRect: NSRect? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    /// Matches `MKMapView`, which is flipped: origin at the top left.
    ///
    /// Without this the rectangle was drawn in one coordinate system and read
    /// in another. It looked right — the drawing used the same unflipped space
    /// as the mouse — but the box handed to the filter was its mirror about
    /// the middle of the map, so a zone traced over Saint-Galmier selected the
    /// tracks of a band the same distance the other way.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        anchor = convert(event.locationInWindow, from: nil)
        currentRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(anchor.x, point.x), y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, let rect = currentRect else {
            anchor = nil
            return
        }
        anchor = nil
        currentRect = nil
        onSelection?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isEnabled else { return }

        // Faint wash so it's obvious the map is in selection mode.
        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
        bounds.fill()

        guard let rect = currentRect else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.20).setFill()
        rect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }
}
