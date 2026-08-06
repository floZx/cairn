import SwiftUI
import MapKit

/// Single-track map. Uses MKMapView rather than SwiftUI's `Map` because the
/// global map (Task 16) needs MKMapView anyway, and sharing the renderer keeps
/// the two maps looking identical.
struct ActivityMapView: NSViewRepresentable {
    let coordinates: [Coordinate]

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsZoomControls = true
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .controlAccentColor
            renderer.lineWidth = 4
            return renderer
        }
    }
}
