import SwiftUI
import MapKit
import SwiftData

struct GlobalMapView: View {
    let activities: [Activity]
    // `Activity.ID` (the macro-synthesized `PersistentModel` typealias) isn't
    // nameable via dot-syntax outside the file that declares `Activity`, even
    // within the same module — a known SwiftData/macro limitation (see
    // `ActivityListView.selection`). `PersistentIdentifier` is used directly
    // here instead.
    @Binding var selection: PersistentIdentifier?
    @Binding var region: BoundingBox?

    @State private var isSelectingRegion = false

    private var tracks: [[Coordinate]] {
        activities.compactMap {
            let track = $0.simplifiedCoordinates
            return track.count > 1 ? track : nil
        }
    }

    var body: some View {
        TrackMapRepresentable(
            tracks: tracks,
            isSelectingRegion: isSelectingRegion,
            onRegionSelected: { box in
                region = box
                isSelectingRegion = false
            }
        )
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                Toggle(isOn: $isSelectingRegion) {
                    Label("Sélectionner une zone", systemImage: "dot.viewfinder")
                }
                .toggleStyle(.button)
                .help("Tracez un rectangle sur la carte pour ne garder que les activités qui le traversent")

                if region != nil {
                    Button {
                        region = nil
                    } label: {
                        Label("Effacer la zone", systemImage: "xmark.circle")
                    }
                }
            }
            .padding()
        }
        .overlay(alignment: .bottomLeading) {
            Text(
                tracks.count == 1
                    ? "1 trace affichée" : "\(tracks.count) traces affichées"
            )
            .font(.caption)
            .padding(6)
            .background(.regularMaterial, in: .rect(cornerRadius: 6))
            .padding()
        }
        .navigationTitle("Carte globale")
    }
}

/// All tracks in a single `MKMultiPolyline`.
///
/// One overlay per activity brings MapKit to its knees at a few thousand
/// activities; one multi-polyline renders the same geometry in a single pass.
/// The thin translucent stroke also gives repeated routes a heatmap look for
/// free.
struct TrackMapRepresentable: NSViewRepresentable {
    let tracks: [[Coordinate]]
    let isSelectingRegion: Bool
    let onRegionSelected: (BoundingBox) -> Void

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsZoomControls = true

        let overlay = SelectionOverlayView()
        overlay.onSelection = { rect in
            guard let box = context.coordinator.boundingBox(for: rect, in: mapView)
            else { return }
            onRegionSelected(box)
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: mapView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: mapView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
        ])
        context.coordinator.selectionOverlay = overlay
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.selectionOverlay?.isEnabled = isSelectingRegion
        // Panning must stop while drawing, otherwise the drag moves the map.
        mapView.isScrollEnabled = !isSelectingRegion

        // Keyed on a signature rather than the count: a filter change can swap
        // which activities are shown while leaving the count identical, and a
        // count-only guard would then leave the previous tracks on screen.
        var hasher = Hasher()
        hasher.combine(tracks.count)
        for track in tracks { hasher.combine(track.count) }
        let signature = hasher.finalize()

        guard context.coordinator.renderedSignature != signature else { return }
        context.coordinator.renderedSignature = signature

        mapView.removeOverlays(mapView.overlays)
        guard !tracks.isEmpty else { return }

        let polylines = tracks.map {
            MKPolyline(coordinates: $0.map(\.clLocation), count: $0.count)
        }
        let multi = MKMultiPolyline(polylines)
        mapView.addOverlay(multi)

        // Opens where the user actually trains rather than framing every track:
        // one ride abroad would otherwise zoom out to a continent. Falls back to
        // the full extent if no dense area can be found.
        let rect = TrackDensity.focusRegion(for: tracks)
            .map(Self.mapRect(for:)) ?? multi.boundingMapRect
        mapView.setVisibleMapRect(
            rect,
            edgePadding: NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
            animated: false
        )
    }

    private static func mapRect(for box: BoundingBox) -> MKMapRect {
        let topLeft = MKMapPoint(
            CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.minLon)
        )
        let bottomRight = MKMapPoint(
            CLLocationCoordinate2D(latitude: box.minLat, longitude: box.maxLon)
        )
        return MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderedSignature: Int?
        weak var selectionOverlay: SelectionOverlayView?

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            let renderer = MKMultiPolylineRenderer(overlay: overlay)
            renderer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.45)
            renderer.lineWidth = 2
            return renderer
        }

        func boundingBox(for rect: NSRect, in mapView: MKMapView) -> BoundingBox? {
            guard rect.width > 4, rect.height > 4 else { return nil }
            let topLeft = mapView.convert(
                NSPoint(x: rect.minX, y: rect.maxY), toCoordinateFrom: mapView
            )
            let bottomRight = mapView.convert(
                NSPoint(x: rect.maxX, y: rect.minY), toCoordinateFrom: mapView
            )
            return BoundingBox(
                minLat: min(topLeft.latitude, bottomRight.latitude),
                maxLat: max(topLeft.latitude, bottomRight.latitude),
                minLon: min(topLeft.longitude, bottomRight.longitude),
                maxLon: max(topLeft.longitude, bottomRight.longitude)
            )
        }
    }
}
