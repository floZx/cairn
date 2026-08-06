import SwiftUI
import MapKit

/// The available map backgrounds.
///
/// MapKit offers no topographic option at all — no contour lines, no marked
/// trails — so the last case leaves Apple's tiles behind and draws
/// OpenTopoMap's instead. That is the only case that talks to a third party.
enum MapStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case relief
    case satellite
    case hybrid
    case topo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Plan"
        case .relief: "Plan avec relief"
        case .satellite: "Satellite"
        case .hybrid: "Satellite et noms"
        case .topo: "Topographique (2D)"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "map"
        case .relief: "mountain.2"
        case .satellite: "globe.europe.africa"
        case .hybrid: "globe.europe.africa.fill"
        case .topo: "mountain.2.circle"
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
        case .topo:
            // Hidden under the tile layer, but a configuration is still
            // required; muted keeps Apple's labels from bleeding through at the
            // zoom levels OpenTopoMap does not cover.
            MKStandardMapConfiguration(emphasisStyle: .muted)
        }
    }

    var usesTopoTiles: Bool { self == .topo }

    /// Required by OpenTopoMap's licence, and shown whenever their tiles are.
    static let topoAttribution = "© OpenStreetMap · SRTM · OpenTopoMap (CC-BY-SA)"

    /// Remembered across launches, and shared by both maps.
    static let storageKey = "mapStyle"
}

/// OpenTopoMap raster tiles: contour lines, marked trails, shaded relief.
///
/// `canReplaceMapContent` is deliberately left off. Telling MapKit it may skip
/// its own basemap made it drop rendered tiles as the camera moved; keeping
/// Apple's map underneath costs a second set of tiles and lets its labels show
/// through the gaps, but the layer stays put — confirmed in use.
///
/// Their usage policy asks for reasonable, non-bulk use — an app browsing one
/// athlete's own tracks sits well inside that.
final class TopoTileOverlay: MKTileOverlay {
    /// Tiles are fetched through a session with a real disk cache, so panning
    /// back over ground already seen costs nothing and survives a relaunch.
    /// MapKit's default loader gives no such guarantee, and the server itself
    /// declares the tiles cacheable for a week.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: URL.cachesDirectory.appending(path: "StravaLocal/TopoTiles")
        )
        // Map tiles change on the scale of months: a cached tile is preferred
        // even once nominally stale, rather than re-fetched on every pan.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        // OpenStreetMap-family services ask that clients identify themselves.
        configuration.httpAdditionalHeaders = [
            "User-Agent": "StravaLocal (personal use)"
        ]
        // A map view asks for twenty-odd tiles at once; a handful of
        // connections is both politer and less likely to trip the server's
        // faulty path below.
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    init() {
        super.init(urlTemplate: "https://tile.opentopomap.org/{z}/{x}/{y}.png")
        canReplaceMapContent = false
        minimumZ = 2
        // OpenTopoMap publishes nothing beyond 17; asking for more returns
        // blanks rather than an upscaled tile.
        maximumZ = 17
    }

    /// Retries a couple of times before giving up.
    ///
    /// The server intermittently emits an `Upgrade: h2,h2c` header *inside* an
    /// HTTP/2 response, which the specification forbids and which URLSession
    /// rejects outright — measured at roughly one request in ten, leaving the
    /// map pockmarked with tiles that never arrive. Forcing HTTP/1.1 fixes it
    /// completely (20/20 against 18/20 in testing), but URLSession offers no
    /// public way to choose the protocol, so retries stand in: three attempts
    /// take a 10% failure rate down to about one in a thousand.
    override func loadTile(at path: MKTileOverlayPath) async throws -> Data {
        let request = URLRequest(url: url(forTilePath: path))
        var lastError: any Error = URLError(.cannotLoadFromNetwork)

        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(120 * attempt))
            }
            do {
                let (data, _) = try await Self.session.data(for: request)
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
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

        // Raster tiles are flat images, and MapKit does not draw an overlay under
        // a pitched or rotated camera: the layer flickers in and out as the map
        // moves. Rather than half-render it, the camera is held flat and
        // north-up while these tiles are in use — a raster has no relief to show
        // in 3D anyway, since Apple computes that from its own terrain data.
        isPitchEnabled = !style.usesTopoTiles
        isRotateEnabled = !style.usesTopoTiles

        if style.usesTopoTiles, camera.pitch != 0 || camera.heading != 0 {
            setCamera(
                MKMapCamera(
                    lookingAtCenter: camera.centerCoordinate,
                    fromDistance: camera.altitude,
                    pitch: 0,
                    heading: 0
                ),
                animated: true
            )
        }

        if style.usesTopoTiles {
            guard state.topoOverlay == nil else { return }
            let tiles = TopoTileOverlay()
            insertOverlay(tiles, at: 0, level: .aboveRoads)
            state.topoOverlay = tiles
        } else if let existing = state.topoOverlay {
            removeOverlay(existing)
            state.topoOverlay = nil
        }
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
        .padding(6)
        .background(.regularMaterial, in: .rect(cornerRadius: 6))
        .help("Choisir le fond de carte")
    }
}

/// Shown only where a licence requires it.
struct MapAttribution: View {
    let style: MapStyle

    var body: some View {
        if style.usesTopoTiles {
            Text(MapStyle.topoAttribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.regularMaterial, in: .rect(cornerRadius: 4))
        }
    }
}
