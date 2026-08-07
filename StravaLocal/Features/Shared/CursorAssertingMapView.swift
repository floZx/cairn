import MapKit

/// A map view that claims a cursor over itself, and the only thing that does.
///
/// `MKMapView` asserts no cursor of its own, and AppKit only changes the pointer
/// when it enters something that asks for one. So a cursor picked up elsewhere
/// survives right across a map: hover the divider beside it, move onto the map,
/// and the resize double-arrow stays. The panes on the other side of that divider
/// never showed it, because SwiftUI's views assert their own.
///
/// Both of AppKit's mechanisms are used. A cursor rect is the declarative one, but
/// `resetCursorRects` may never be called on a layer-hosted view like this, and a
/// front subview covering the map can shadow the request — the region-selection
/// overlay is exactly such a subview, and the global map was the only one still
/// affected once the rect alone was in place. A tracking area is geometric and
/// answers regardless. The two cannot disagree: they claim the same cursor.
///
/// Owning it here rather than in that overlay puts one object in charge. When the
/// region selector is armed it sets `claimedCursor` and the crosshair follows,
/// instead of two views each asserting something over the same pixels.
final class CursorAssertingMapView: MKMapView {
    /// What the pointer becomes over this map. A crosshair while a region is being
    /// drawn, the plain arrow the rest of the time.
    var claimedCursor: NSCursor = .arrow {
        didSet {
            guard claimedCursor != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    private var cursorArea: NSTrackingArea?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: claimedCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea { removeTrackingArea(cursorArea) }
        // `inVisibleRect` keeps it correct as the pane is resized, which happens
        // every time the detail column opens or collapses.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        cursorArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        claimedCursor.set()
    }
}
