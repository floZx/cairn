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
    /// Les préférences : à quel point les fonds topographiques s'assombrissent
    /// en mode sombre, de 0 (tuiles laissées claires) à 1.
    static let darkLevelKey = "mapDarkLevel"
    static let defaultDarkLevel = 0.5
    static var storedDarkLevel: Double {
        UserDefaults.standard.object(forKey: darkLevelKey) as? Double ?? defaultDarkLevel
    }

    case standard
    case satellite
    case hybrid
    case ignTopo
    case openTopo

    var id: String { rawValue }

    /// Le fond que `i` met à la place : Plan depuis l'IGN, l'IGN depuis tout
    /// le reste.
    var toggledTopo: MapStyle { self == .ignTopo ? .standard : .ignTopo }

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

    /// Whether this background is drawn in three dimensions — terrain relief, and
    /// a camera that leans over it.
    ///
    /// Apple's own basemaps only, and for two measured reasons. MapKit gives a
    /// third-party raster layer a single zoom level for the whole visible rect, so
    /// a leaning camera stretches it: IGN tiles from two zoom levels ended up in
    /// one image, place names outsized in the distance. And realistic elevation
    /// drapes overlays onto a terrain mesh, which resamples them — the track came
    /// out thick and smeared, the direction chevrons no longer squarely on it.
    ///
    /// Nothing is lost on the topographic backgrounds: the relief is drawn into
    /// the tiles themselves, as contour lines and hillshading.
    var rendersInThreeDimensions: Bool { tileSource == nil }

    var configuration: MKMapConfiguration {
        let elevation: MKMapConfiguration.ElevationStyle =
            rendersInThreeDimensions ? .realistic : .flat
        switch self {
        case .standard:
            return MKStandardMapConfiguration(elevationStyle: elevation)
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: elevation)
        case .hybrid:
            return MKHybridMapConfiguration(elevationStyle: elevation)
        case .ignTopo, .openTopo:
            // Drawn under the tile layer and hidden once it lands, but it is
            // what shows during a zoom before the new level's tiles are ready —
            // see `RasterTileOverlay`. Muted keeps Apple's labels discreet in
            // that moment.
            return MKStandardMapConfiguration(
                elevationStyle: elevation, emphasisStyle: .muted
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

    /// Remembered across launches, and shared by the activity's map, the
    /// expanded one and the comparison map.
    static let storageKey = "mapStyle"

    /// La carte globale a le sien : on peut vouloir Plan pour voir sept cents
    /// traces d'un coup et l'IGN pour lire une sortie. Demandé le 2 octobre
    /// 2026.
    static let globalStorageKey = "mapStyleGlobal"

    /// Le fond de la carte globale tant qu'elle n'en a pas choisi : celui que
    /// toutes les cartes partageaient jusque-là, pour que la séparation ne
    /// change rien à l'écran.
    static var globalDefault: MapStyle {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MapStyle.init) ?? .standard
    }
}
