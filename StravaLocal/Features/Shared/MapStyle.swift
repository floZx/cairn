import SwiftUI
import MapKit

/// The available map backgrounds.
///
/// MapKit offers no topographic option at all — no contour lines, no marked
/// trails — so the last case leaves Apple's tiles behind and draws
/// OpenTopoMap's instead. That is the only case that talks to a third party.
/// A raster tile layer to draw instead of Apple's basemap.
struct TileSource: Sendable {
    let urlTemplate: String
    /// Shown on screen whenever the layer is; both providers require it.
    let attribution: String
    let maximumZ: Int
}

enum MapStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case relief
    case satellite
    case hybrid
    case ignTopo
    case openTopo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Plan"
        case .relief: "Plan avec relief"
        case .satellite: "Satellite"
        case .hybrid: "Satellite et noms"
        case .ignTopo: "Topographique IGN"
        case .openTopo: "Topographique monde"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "map"
        case .relief: "mountain.2"
        case .satellite: "globe.europe.africa"
        case .hybrid: "globe.europe.africa.fill"
        case .ignTopo: "mountain.2.circle.fill"
        case .openTopo: "mountain.2.circle"
        }
    }

    var configuration: MKMapConfiguration {
        switch self {
        case .standard:
            MKStandardMapConfiguration(elevationStyle: .flat)
        case .relief:
            MKStandardMapConfiguration(elevationStyle: .realistic)
        case .satellite:
            MKImageryMapConfiguration(elevationStyle: .realistic)
        case .hybrid:
            MKHybridMapConfiguration(elevationStyle: .realistic)
        case .ignTopo, .openTopo:
            // Drawn under the tile layer and mostly hidden; muted keeps Apple's
            // labels discreet where a tile has yet to arrive. Realistic
            // elevation is kept on so a pitched camera has terrain to drape the
            // raster over.
            MKStandardMapConfiguration(
                elevationStyle: .realistic, emphasisStyle: .muted
            )
        }
    }

    /// The raster layer this style draws, if any.
    var tileSource: TileSource? {
        switch self {
        case .standard, .relief, .satellite, .hybrid:
            nil
        case .ignTopo:
            // France only, but contour lines, named woods, hamlets and tracks —
            // and a server that answers every request. The true 1:25000 SCAN25
            // needs a licence and is refused to anonymous clients.
            TileSource(
                urlTemplate: "https://data.geopf.fr/wmts?SERVICE=WMTS"
                    + "&REQUEST=GetTile&VERSION=1.0.0&STYLE=normal"
                    + "&TILEMATRIXSET=PM&FORMAT=image/png"
                    + "&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2"
                    + "&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}",
                attribution: "© IGN — Géoplateforme",
                maximumZ: 19
            )
        case .openTopo:
            TileSource(
                urlTemplate: "https://tile.opentopomap.org/{z}/{x}/{y}.png",
                attribution: "© OpenStreetMap · SRTM · OpenTopoMap (CC-BY-SA)",
                maximumZ: 17
            )
        }
    }

    var usesTopoTiles: Bool { tileSource != nil }

    /// Remembered across launches, and shared by both maps.
    static let storageKey = "mapStyle"
}

/// A raster basemap drawn instead of Apple's.
///
/// Deliberately the plainest possible subclass: MapKit's own loader issues
/// ordinary GETs through the shared URLSession, which honours the servers'
/// cache headers — both declare their tiles valid for days. An earlier version
/// added a private session, a disk cache, a four-connection cap and retries,
/// and tiles stopped arriving; Leaflet fetching the very same tiles with plain
/// GETs is flawless, so the extra machinery was the problem, not the servers.
///
/// `canReplaceMapContent` is on: Apple's basemap is not drawn underneath, so it
/// no longer flashes through while the camera moves. It was briefly turned off
/// while chasing tiles that vanished, but that had another cause entirely —
/// MapKit properties being rewritten on every view update. The cost is that a
/// tile still in flight leaves blank ground rather than a fallback map.
final class RasterTileOverlay: MKTileOverlay {
    init(source: TileSource) {
        super.init(urlTemplate: source.urlTemplate)
        canReplaceMapContent = true
        minimumZ = 2
        maximumZ = source.maximumZ
    }
}

/// What a map view has already been told, so it is not told again.
struct MapStyleState {
    var applied: MapStyle?
    var topoOverlay: MKTileOverlay?
}

extension MKMapView {
    /// Applies a style, adding or removing the topo layer as needed.
    ///
    /// The tile layer is inserted at the bottom so a track always draws over it.
    func apply(_ style: MapStyle, state: inout MapStyleState) {
        // Reassigning `preferredConfiguration` makes MapKit reload its basemap
        // and drop whatever the tile overlay had already rendered. Since this
        // runs on every SwiftUI update — including every mouse move while a
        // chart is hovered — doing it unconditionally made tiles blink out.
        guard state.applied != style else { return }
        state.applied = style

        preferredConfiguration = style.configuration

        // No 2D lock on the raster layers. An earlier version pinned the camera
        // flat, on the theory that MapKit would not draw a tile overlay under a
        // pitched view — but the tiles were rendering all along, in a rotated
        // view, and what actually failed was tile loading. Pitch and rotation
        // stay available everywhere.

        if let source = style.tileSource {
            guard state.topoOverlay == nil else { return }
            let tiles = RasterTileOverlay(source: source)
            insertOverlay(tiles, at: 0, level: .aboveRoads)
            state.topoOverlay = tiles
        } else if let existing = state.topoOverlay {
            removeOverlay(existing)
            state.topoOverlay = nil
        }
    }
}

/// Carries zoom requests from SwiftUI buttons down to the map view.
///
/// MapKit's own zoom controls cannot be restyled, and they are white pills that
/// vanish against a pale topographic tile. Ours share the backing every other
/// map control uses, and sit clear of the attribution.
@Observable
final class MapZoomController {
    /// Net zoom steps requested. The map view applies the difference and
    /// remembers where it got to.
    private(set) var steps = 0

    func zoomIn() { steps += 1 }
    func zoomOut() { steps -= 1 }
}

/// The +/− pair, styled like the rest.
struct MapZoomButtons: View {
    let controller: MapZoomController

    var body: some View {
        VStack(spacing: 4) {
            Button { controller.zoomIn() } label: {
                Image(systemName: "plus").frame(width: 12, height: 12)
            }
            .help("Zoomer")
            Divider().frame(width: 20)
            Button { controller.zoomOut() } label: {
                Image(systemName: "minus").frame(width: 12, height: 12)
            }
            .help("Dézoomer")
        }
        .buttonStyle(.plain)
        .mapControl()
    }
}

extension MKMapView {
    /// Applies whatever zoom steps have accumulated since the last call.
    func applyZoom(from controller: MapZoomController, applied: inout Int) {
        let delta = controller.steps - applied
        guard delta != 0 else { return }
        applied = controller.steps

        // Halving or doubling the altitude is one zoom level, which is what the
        // scroll wheel and the pinch gesture do.
        let factor = pow(0.5, Double(delta))
        let altitude = max(200, min(camera.altitude * factor, 40_000_000))
        setCamera(
            MKMapCamera(
                lookingAtCenter: camera.centerCoordinate,
                fromDistance: altitude,
                pitch: camera.pitch,
                heading: camera.heading
            ),
            animated: true
        )
    }
}

extension View {
    /// Standard treatment for a control floating over a map: a plain button has
    /// no contrast against either a pale topographic tile or a dark satellite
    /// image, so every one of them carries the same translucent backing.
    func mapControl() -> some View {
        padding(6)
            .background(.regularMaterial, in: .rect(cornerRadius: 6))
    }
}

/// Compact background picker, shared by the activity map and the global map.
struct MapStylePicker: View {
    @Binding var style: MapStyle

    var body: some View {
        Menu {
            Picker("Fond de carte", selection: $style) {
                ForEach(MapStyle.allCases) { style in
                    Label(style.displayName, systemImage: style.symbolName)
                        .tag(style)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(style.displayName, systemImage: style.symbolName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .mapControl()
        .help("Choisir le fond de carte")
    }
}

/// Shown only where a licence requires it.
struct MapAttribution: View {
    let style: MapStyle

    var body: some View {
        if let source = style.tileSource {
            Text(source.attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.regularMaterial, in: .rect(cornerRadius: 4))
        }
    }
}
