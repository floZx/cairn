import AppKit

/// Transparent layer above the map that captures a rubber-band drag.
///
/// Drawing the rectangle here rather than in MKMapView keeps map gestures and
/// selection gestures from fighting over the same drag: when disabled, the view
/// declines every hit test and the map behaves exactly as if it weren't there.
final class SelectionOverlayView: NSView {
    var isEnabled = false {
        didSet {
            if !isEnabled { currentRect = nil }
            needsDisplay = true
            // AppKit only recomputes cursor rects when the window is told to, so
            // without this the crosshair arrived late on entering selection mode
            // and outstayed its welcome on leaving it.
            window?.invalidateCursorRects(for: self)
        }
    }
    var onSelection: ((NSRect) -> Void)?

    private var anchor: NSPoint?
    private var currentRect: NSRect? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

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

    override func resetCursorRects() {
        guard isEnabled else { return }
        addCursorRect(bounds, cursor: .crosshair)
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
