import SwiftUI
import MapKit
import SwiftData

struct GlobalMapView: View {
    let activities: [Activity]
    @Binding var region: BoundingBox?
    /// Nil when the map is already filling the window, which hides the button.
    var onExpand: (() -> Void)?
    /// Clicking a track opens it in the detail pane.
    var onSelect: ((PersistentIdentifier) -> Void)?

    @State private var isSelectingRegion = false
    @AppStorage(MapStyle.storageKey) private var style: MapStyle = .standard

    /// Newest first, so the palette slot a track gets never changes between
    /// redraws — the same reason the comparison map sorts before colouring.
    private var tracks: [GlobalTrack] {
        activities
            .sorted { $0.startDate > $1.startDate }
            .compactMap { activity -> (PersistentIdentifier, [Coordinate])? in
                let track = activity.simplifiedCoordinates
                return track.count > 1 ? (activity.id, track) : nil
            }
            .enumerated()
            .map { index, track in
                GlobalTrack(
                    id: track.0,
                    coordinates: track.1,
                    colorIndex: index % TrackPalette.colors.count
                )
            }
    }

    var body: some View {
        TrackMapRepresentable(
            tracks: tracks,
            isSelectingRegion: isSelectingRegion,
            style: style,
            onSelect: onSelect,
            onRegionSelected: { box in
                region = box
                isSelectingRegion = false
            }
        )
        .mapChrome(style: $style) {
            if let onExpand {
                MapExpandButton(action: onExpand)
            }

            // A button rather than a Toggle: there is no plain toggle style,
            // so `.toggleStyle(.button)` kept its own frame and drew a second
            // border inside the shared backing. Engagement shows in the tint.
            Button {
                isSelectingRegion.toggle()
            } label: {
                Label("Sélectionner une zone", systemImage: "dot.viewfinder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelectingRegion ? Color.accentColor : Color.primary)
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

/// One track of the global map, with the palette slot it is drawn in.
struct GlobalTrack {
    let id: PersistentIdentifier
    let coordinates: [Coordinate]
    let colorIndex: Int
}

/// A multi-polyline per palette colour.
///
/// The colours alternate so overlapping routes can be told apart, but not by
/// giving each activity its own overlay — that brings MapKit to its knees at a
/// few thousand of them. Grouping by colour keeps it to eight overlays whatever
/// the library's size, since a renderer carries one stroke colour for everything
/// it draws. The thin translucent stroke still gives repeated routes a heatmap
/// look for free.
struct TrackMapRepresentable: NSViewRepresentable {
    let tracks: [GlobalTrack]
    let isSelectingRegion: Bool
    let style: MapStyle
    let onSelect: ((PersistentIdentifier) -> Void)?
    let onRegionSelected: (BoundingBox) -> Void

    func makeNSView(context: Context) -> MKMapView {
        let mapView = CursorAssertingMapView()
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

        // A click opens the track under the cursor. It does not swallow the
        // event: without this the map would stop panning and lose its
        // double-click zoom, and the selection overlay declines hit tests while
        // disabled so the two never compete.
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        click.delaysPrimaryMouseButtonEvents = false
        mapView.addGestureRecognizer(click)
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
            (mapView as? CursorAssertingMapView)?.claimedCursor =
                isSelectingRegion ? .crosshair : .arrow
        }

        context.coordinator.onSelect = onSelect

        // Keyed on a signature rather than the count: a filter change can swap
        // which activities are shown while leaving the count identical, and a
        // count-only guard would then leave the previous tracks on screen.
        var hasher = Hasher()
        hasher.combine(tracks.count)
        for track in tracks {
            hasher.combine(track.id)
            hasher.combine(track.coordinates.count)
            hasher.combine(track.colorIndex)
        }
        let signature = hasher.finalize()

        guard context.coordinator.renderedSignature != signature else { return }
        context.coordinator.renderedSignature = signature

        mapView.removeOverlays(mapView.overlays.filter { !($0 is MKTileOverlay) })
        // Kept for hit testing, which MapKit does not do for overlay renderers.
        context.coordinator.hitIDs = tracks.map(\.id)
        context.coordinator.hitPoints = tracks.map {
            $0.coordinates.map { MKMapPoint($0.clLocation) }
        }
        guard !tracks.isEmpty else { return }

        // Grouped by colour, so the overlay count is the palette's size rather
        // than the library's.
        let grouped = Dictionary(grouping: tracks, by: \.colorIndex)
        let overlays = grouped.keys.sorted().map { slot -> ColoredMultiPolyline in
            let lines = grouped[slot, default: []].map {
                MKPolyline(
                    coordinates: $0.coordinates.map(\.clLocation),
                    count: $0.coordinates.count
                )
            }
            let multi = ColoredMultiPolyline(lines)
            multi.color = TrackPalette.color(at: slot)
            return multi
        }
        mapView.addTrackOverlays(overlays)
        let multi = MKMultiPolyline(overlays.flatMap(\.polylines))

        // Opens where the user actually trains rather than framing every track:
        // one ride abroad would otherwise zoom out to a continent. Falls back to
        // the full extent if no dense area can be found.
        let rect = TrackDensity.focusRegion(for: tracks.map(\.coordinates))
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
        weak var selectionOverlay: SelectionOverlayView?
        var onSelect: ((PersistentIdentifier) -> Void)?
        /// The drawn geometry, in the same order as `hitIDs`. Overlays are grouped
        /// by colour for drawing, which loses the per-activity mapping a click
        /// needs, so it is kept here instead.
        var hitIDs: [PersistentIdentifier] = []
        var hitPoints: [[MKMapPoint]] = []

        /// How near a click has to land, in screen points.
        ///
        /// Generous on purpose: a 2.5-point line is a hard target with a mouse,
        /// and picking nothing is the outcome a user reads as "it doesn't work".
        private static let hitTolerance: Double = 12

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView,
                  isSelectingRegion != true,
                  !hitPoints.isEmpty,
                  mapView.bounds.width > 0
            else { return }

            let location = recognizer.location(in: mapView)
            let clicked = MKMapPoint(
                mapView.convert(location, toCoordinateFrom: mapView)
            )
            // Screen points into map points, which is what the geometry works in.
            let scale = mapView.visibleMapRect.width / Double(mapView.bounds.width)
            guard let index = TrackHitTest.nearestTrack(
                to: clicked, in: hitPoints, within: Self.hitTolerance * scale
            ) else { return }
            onSelect?(hitIDs[index])
        }

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            let renderer = MKMultiPolylineRenderer(overlay: overlay)
            // Still translucent, so repeated routes build up into a heatmap, but
            // no longer so faint that a single passage vanishes into a satellite
            // tile. Overlaps still darken — 0.7 then 0.91 then 0.97 — they just
            // saturate sooner, which is the right trade when one ride has to be
            // findable in the first place.
            let colour = (overlay as? ColoredMultiPolyline)?.color
                ?? TrackPalette.colors[0]
            renderer.strokeColor = colour.withAlphaComponent(0.7)
            renderer.lineWidth = 2.5
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
