import SwiftUI
import MapKit

/// Single-track map, with an optional point highlighted along the way.
///
/// Uses MKMapView rather than SwiftUI's `Map` because the global map needs
/// MKMapView anyway, and sharing the renderer keeps the two maps looking
/// identical.
struct ActivityMapView: NSViewRepresentable {
    let coordinates: [Coordinate]
    /// Follows the cursor over the charts. Updating it must not disturb the
    /// map's framing, which is why the track is only rebuilt when it changes.
    var highlight: Coordinate?

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsZoomControls = true
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        var hasher = Hasher()
        hasher.combine(coordinates.count)
        hasher.combine(coordinates.first)
        hasher.combine(coordinates.last)
        let signature = hasher.finalize()

        // Rebuilding and re-framing on every update would fight the user's own
        // zoom, and would snap the map on every mouse move once a chart is
        // being hovered.
        if coordinator.renderedSignature != signature {
            coordinator.renderedSignature = signature
            mapView.removeOverlays(mapView.overlays)
            coordinator.highlightCircle = nil

            guard coordinates.count > 1 else { return }
            let polyline = MKPolyline(
                coordinates: coordinates.map(\.clLocation), count: coordinates.count
            )
            mapView.addOverlay(polyline)
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                animated: false
            )
        }

        if let existing = coordinator.highlightCircle {
            mapView.removeOverlay(existing)
            coordinator.highlightCircle = nil
        }
        guard let highlight else { return }

        // Radius follows the zoom level so the marker stays the same apparent
        // size whether the whole ride or one street is on screen.
        let visibleMetres = mapView.region.span.latitudeDelta * 111_000
        let circle = MKCircle(
            center: highlight.clLocation, radius: max(15, visibleMetres / 70)
        )
        mapView.addOverlay(circle)
        coordinator.highlightCircle = circle
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderedSignature: Int?
        var highlightCircle: MKCircle?

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = .controlAccentColor
                renderer.strokeColor = .white
                renderer.lineWidth = 2
                return renderer
            }
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .controlAccentColor
            renderer.lineWidth = 4
            return renderer
        }
    }
}
