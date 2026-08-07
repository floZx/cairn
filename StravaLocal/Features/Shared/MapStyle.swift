import MapKit

/// A raster tile layer drawn instead of Apple's basemap.
struct TileSource: Sendable {
    let urlTemplate: String
    /// Shown on screen whenever the layer is; both providers require it.
    let attribution: String
    let maximumZ: Int
}

/// The available map backgrounds.
///
/// Apple provides four looks but nothing topographic — no contour lines, no
/// marked trails — so the last two cases draw third-party raster tiles
/// instead. Those are the only styles that talk to a server other than
/// Apple's.
enum MapStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case satellite
    case hybrid
    case ignTopo
    case openTopo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Plan"
        case .satellite: "Satellite"
        case .hybrid: "Satellite et noms"
        case .ignTopo: "Topographique IGN"
        case .openTopo: "Topographique monde"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.europe.africa"
        case .hybrid: "globe.europe.africa.fill"
        case .ignTopo: "mountain.2.circle.fill"
        case .openTopo: "mountain.2.circle"
        }
    }

    var configuration: MKMapConfiguration {
        switch self {
        // Flat everywhere, and that is a considered retreat. Realistic elevation
        // drapes overlays onto a terrain mesh, which resamples them: the track
        // came out thick and smeared and the direction chevrons no longer landed
        // squarely on it. The camera still leans over — perspective does not
        // require terrain — and on the topographic backgrounds the relief is
        // still plainly there, drawn into the tiles themselves as contour lines
        // and hillshading.
        case .standard:
            MKStandardMapConfiguration(elevationStyle: .flat)
        case .satellite:
            MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid:
            MKHybridMapConfiguration(elevationStyle: .flat)
        case .ignTopo, .openTopo:
            // Drawn under the tile layer and hidden once it lands, but it is
            // what shows during a zoom before the new level's tiles are ready —
            // see `RasterTileOverlay`. Muted keeps Apple's labels discreet in
            // that moment.
            MKStandardMapConfiguration(
                elevationStyle: .flat, emphasisStyle: .muted
            )
        }
    }

    /// The raster layer this style draws, if any.
    var tileSource: TileSource? {
        switch self {
        case .standard, .satellite, .hybrid:
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

    /// Remembered across launches, and shared by every map in the app.
    static let storageKey = "mapStyle"
}
