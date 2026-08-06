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
    /// Nil when the map is already filling the window, which hides the button.
    var onExpand: (() -> Void)?

    @State private var isSelectingRegion = false
    @AppStorage(MapStyle.storageKey) private var style: MapStyle = .standard
    @AppStorage(TrackColor.storageKey) private var trackColor: TrackColor = .accent

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
            style: style,
            trackColor: trackColor,
            onRegionSelected: { box in
                region = box
                isSelectingRegion = false
            }
        )
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                MapStylePicker(style: $style)

                if let onExpand {
                    Button(action: onExpand) {
                        Label(
                            "Agrandir",
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .mapControl()
                    .help("Afficher la carte sur toute la fenêtre")
                }

                Toggle(isOn: $isSelectingRegion) {
                    Label("Sélectionner une zone", systemImage: "dot.viewfinder")
                }
                .toggleStyle(.button)
                // Same backing as every other map control. Its own button chrome
                // was legible on Apple's dark plan but vanished on a pale
                // topographic tile.
                .mapControl()
                .help("Tracez un rectangle sur la carte pour ne garder que les activités qui le traversent")

                if region != nil {
                    Button {
                        region = nil
                    } label: {
                        Label("Effacer la zone", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .mapControl()
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
        // Centred, clear of Apple's legal link on the left and of the compass
        // and zoom buttons on the right.
        .overlay(alignment: .bottom) {
            MapAttribution(style: style).padding(8)
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
    let style: MapStyle
    let trackColor: TrackColor
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
        mapView.apply(style, state: &context.coordinator.mapStyleState)

        // Assigned only on a real change. Writing MapKit properties on every
        // SwiftUI update — and this view is rebuilt whenever the filtered
        // activity list is recomputed — resets internal state and discards
        // tiles in flight. That is what made the topo layer work on the
        // activity map but not here.
        if context.coordinator.isSelectingRegion != isSelectingRegion {
            context.coordinator.isSelectingRegion = isSelectingRegion
            context.coordinator.selectionOverlay?.isEnabled = isSelectingRegion
            // Panning must stop while drawing, otherwise the drag moves the map.
            mapView.isScrollEnabled = !isSelectingRegion
        }

        // Keyed on a signature rather than the count: a filter change can swap
        // which activities are shown while leaving the count identical, and a
        // count-only guard would then leave the previous tracks on screen.
        var hasher = Hasher()
        hasher.combine(tracks.count)
        for track in tracks { hasher.combine(track.count) }
        // In the signature so changing the colour redraws: MapKit keeps its
        // renderers, and a new stroke colour alone would not reach the screen.
        hasher.combine(trackColor)
        let signature = hasher.finalize()

        guard context.coordinator.renderedSignature != signature else { return }
        context.coordinator.renderedSignature = signature
        context.coordinator.trackColor = trackColor

        mapView.removeOverlays(mapView.overlays.filter { !($0 is MKTileOverlay) })
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
        var isSelectingRegion: Bool?
        var mapStyleState = MapStyleState()
        var trackColor: TrackColor = .accent
        weak var selectionOverlay: SelectionOverlayView?

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            let renderer = MKMultiPolylineRenderer(overlay: overlay)
            // Translucent so repeated routes build up into a heatmap.
            renderer.strokeColor = trackColor.nsColor.withAlphaComponent(0.45)
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
