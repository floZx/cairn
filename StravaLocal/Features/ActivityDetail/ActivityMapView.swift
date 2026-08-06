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
    var style: MapStyle = .standard
    var zoom: MapZoomController?

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        // Ours instead: Apple's cannot be restyled and disappear against a pale
        // topographic tile.
        mapView.showsZoomControls = false
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        mapView.apply(style, state: &coordinator.mapStyleState)
        if let zoom {
            mapView.applyZoom(from: zoom, applied: &coordinator.appliedZoom)
        }

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
            mapView.removeOverlays(
                mapView.overlays.filter { !($0 is MKTileOverlay) }
            )
            mapView.removeAnnotations(mapView.annotations)
            coordinator.marker = nil

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

        // The marker is an annotation whose coordinate is moved in place, not an
        // overlay torn down and rebuilt: removing and re-adding an overlay on
        // every mouse move makes the marker stutter across the track.
        guard let highlight else {
            if let marker = coordinator.marker {
                mapView.removeAnnotation(marker)
                coordinator.marker = nil
            }
            return
        }

        if let marker = coordinator.marker {
            marker.coordinate = highlight.clLocation
        } else {
            let marker = MKPointAnnotation()
            marker.coordinate = highlight.clLocation
            mapView.addAnnotation(marker)
            coordinator.marker = marker
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderedSignature: Int?
        var marker: MKPointAnnotation?
        var mapStyleState = MapStyleState()
        var appliedZoom = 0

        private static let markerIdentifier = "hover"

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .controlAccentColor
            renderer.lineWidth = 4
            return renderer
        }

        /// A plain dot rather than a pin: this marks a position along the trace,
        /// it is not a place the user can select.
        func mapView(
            _ mapView: MKMapView, viewFor annotation: any MKAnnotation
        ) -> MKAnnotationView? {
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.markerIdentifier
            ) ?? MKAnnotationView(
                annotation: annotation, reuseIdentifier: Self.markerIdentifier
            )
            view.annotation = annotation
            view.canShowCallout = false
            view.isEnabled = false
            view.image = Self.dotImage
            return view
        }

        private static let dotImage: NSImage = {
            let diameter: CGFloat = 14
            let image = NSImage(
                size: NSSize(width: diameter, height: diameter), flipped: false
            ) { rect in
                let inset = rect.insetBy(dx: 2, dy: 2)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: inset).fill()
                NSColor.white.setStroke()
                let outline = NSBezierPath(ovalIn: inset)
                outline.lineWidth = 2
                outline.stroke()
                return true
            }
            return image
        }()
    }
}
