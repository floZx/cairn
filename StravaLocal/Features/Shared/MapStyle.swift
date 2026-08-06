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
        case .topo: "Topographique"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "map"
        case .relief: "mountain.2"
        case .satellite: "globe.europe.africa"
        case .hybrid: "globe.europe.africa.fill"
        case .topo: "chart.line.uptrend.xyaxis"
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
/// `canReplaceMapContent` stops Apple's basemap being drawn underneath, which
/// avoids doubled labels and halves the tiles fetched. Their usage policy asks
/// for reasonable, non-bulk use — an app browsing one athlete's own tracks sits
/// well inside that.
final class TopoTileOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: "https://tile.opentopomap.org/{z}/{x}/{y}.png")
        canReplaceMapContent = true
        minimumZ = 2
        // OpenTopoMap publishes nothing beyond 17; asking for more returns
        // blanks rather than an upscaled tile.
        maximumZ = 17
    }
}

extension MKMapView {
    /// Applies a style, adding or removing the topo layer as needed.
    ///
    /// The tile layer is inserted at the bottom so a track always draws over it.
    func apply(_ style: MapStyle, topoOverlay: inout MKTileOverlay?) {
        preferredConfiguration = style.configuration

        if style.usesTopoTiles {
            guard topoOverlay == nil else { return }
            let tiles = TopoTileOverlay()
            insertOverlay(tiles, at: 0, level: .aboveRoads)
            topoOverlay = tiles
        } else if let existing = topoOverlay {
            removeOverlay(existing)
            topoOverlay = nil
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
