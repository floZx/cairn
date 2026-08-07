import SwiftUI
import MapKit
import SwiftData

/// Several selected activities on one map, each track in its own colour.
///
/// Fills the detail pane in place of a single activity's detail: with more than
/// one activity selected there is no single set of figures to show, but there is
/// a genuine question — how do these routes compare — and a map answers it.
struct ComparisonMapView: View {
    let activities: [Activity]
    /// Nil when the map already fills the window, which hides the button.
    var onExpand: (() -> Void)?

    @AppStorage(MapStyle.storageKey) private var style: MapStyle = .standard

    var body: some View {
        let tracks = ComparedTrack.build(from: activities)
        VStack(spacing: 0) {
            MultiTrackMapRepresentable(tracks: tracks, style: style)
                .mapChrome(style: $style) {
                    if let onExpand {
                        MapExpandButton(action: onExpand)
                    }
                }
            Divider()
            legend(for: tracks)
        }
        .navigationTitle("\(tracks.count) activités sélectionnées")
    }

    private func legend(for tracks: [ComparedTrack]) -> some View {
        // Without a legend the colours mean nothing, so it is part of the
        // feature rather than a decoration. Scrolls, and capped in height so the
        // map keeps most of the pane however many activities are selected.
        List(tracks) { track in
            HStack(spacing: 8) {
                Image(systemName: track.isDrawable ? "circle.fill" : "circle.dotted")
                    .foregroundStyle(Color(nsColor: track.color))
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Label(track.name, systemImage: track.sportSymbol)
                        .lineLimit(1)
                    Text(
                        track.isDrawable
                            ? "\(Format.dateOnly(track.date)) · \(Format.distance(track.distance))"
                            : "\(Format.dateOnly(track.date)) · sans trace"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: 220)
    }
}

/// One selected activity, ready to draw and to list.
struct ComparedTrack: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let date: Date
    let distance: Double
    let sportSymbol: String
    let coordinates: [Coordinate]
    let color: NSColor

    /// Indoor activities have no track at all; the legend says so rather than
    /// leaving the user hunting the map for a colour that was never drawn.
    var isDrawable: Bool { coordinates.count > 1 }

    /// Assigns a colour to each selected activity.
    ///
    /// Sorted first, and that is the whole point: the selection arrives as a
    /// `Set`, so without a deterministic order the colours would shuffle on
    /// every redraw and the legend would stop meaning anything. Newest first,
    /// matching the list's own default.
    static func build(from activities: [Activity]) -> [ComparedTrack] {
        activities
            .sorted { $0.startDate > $1.startDate }
            .enumerated()
            .map { index, activity in
                ComparedTrack(
                    id: activity.id,
                    name: activity.name,
                    date: activity.startLocalDate,
                    distance: activity.distance,
                    sportSymbol: activity.sportType.symbolName,
                    // The simplified track, as on the global map: at pane size
                    // the full stream is indistinguishable and would cost a much
                    // larger decode for every selected activity.
                    coordinates: activity.simplifiedCoordinates,
                    color: TrackPalette.color(at: index)
                )
            }
    }
}

/// A polyline that carries its own colour.
///
/// `MKMapView` asks its delegate for a renderer per overlay and hands over only
/// the overlay, so the colour has to travel with the geometry. One overlay per
/// track rather than an `MKMultiPolyline` — that shares a single renderer, and
/// therefore a single colour, which is exactly what must not happen here.
final class ColoredPolyline: MKPolyline {
    var color: NSColor = .controlAccentColor
}

/// Draws each track in its own colour and frames them all together.
struct MultiTrackMapRepresentable: NSViewRepresentable {
    let tracks: [ComparedTrack]
    let style: MapStyle

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsZoomControls = true
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        mapView.apply(style, state: &coordinator.mapStyleState)

        let signature = Self.signature(of: tracks)
        // Rebuilding on every update would fight the user's own zoom, and
        // re-adding overlays discards the tiles in flight.
        guard coordinator.renderedSignature != signature else { return }
        coordinator.renderedSignature = signature

        mapView.removeOverlays(mapView.overlays.filter { !($0 is MKTileOverlay) })

        let polylines = tracks.filter(\.isDrawable).map { track in
            let line = ColoredPolyline(
                coordinates: track.coordinates.map(\.clLocation),
                count: track.coordinates.count
            )
            line.color = track.color
            return line
        }
        guard !polylines.isEmpty else { return }
        mapView.addOverlays(polylines)

        // The union of every track, unlike the global map's density heuristic:
        // here the user picked these activities deliberately, so all of them
        // have to be on screen even if one is far from the others.
        let rect = polylines.dropFirst().reduce(polylines[0].boundingMapRect) {
            $0.union($1.boundingMapRect)
        }
        mapView.setVisibleMapRect(
            rect,
            edgePadding: NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
    }

    /// Identity of what is drawn, so an unrelated redraw does not reset the map.
    ///
    /// Includes the colours: MapKit keeps its renderers, so a recoloured track
    /// would otherwise never reach the screen.
    static func signature(of tracks: [ComparedTrack]) -> Int {
        var hasher = Hasher()
        hasher.combine(tracks.count)
        for track in tracks {
            hasher.combine(track.id)
            hasher.combine(track.coordinates.count)
            hasher.combine(track.coordinates.first)
            hasher.combine(track.coordinates.last)
            hasher.combine(track.color)
        }
        return hasher.finalize()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderedSignature: Int?
        var mapStyleState = MapStyleState()

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = (overlay as? ColoredPolyline)?.color
                ?? TrackPalette.colors[0]
            renderer.lineWidth = 3
            return renderer
        }
    }
}
