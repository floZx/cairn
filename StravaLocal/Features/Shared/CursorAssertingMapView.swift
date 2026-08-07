import MapKit

/// A map view that claims the arrow cursor over itself.
///
/// `MKMapView` asserts no cursor of its own, and AppKit only changes the pointer
/// when it enters a view that asks for one. So a cursor picked up elsewhere
/// survives all the way across a map: hover the divider beside it, move onto the
/// map, and the resize double-arrow stays. The panes on the other side of that
/// divider do not show the problem because SwiftUI's views assert their own
/// cursors.
///
/// Used by all three maps rather than only the one where it was noticed — the
/// global map sits left of a divider and the comparison map right of one, so the
/// same gap catches both.
///
/// A subview may still claim its own: the region-selection overlay puts a
/// crosshair over the global map, and MapKit's zoom controls keep theirs, both
/// being nearer the pointer in the hierarchy.
final class CursorAssertingMapView: MKMapView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
