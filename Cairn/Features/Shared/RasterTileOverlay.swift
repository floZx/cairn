import MapKit
import CoreImage
import ImageIO
import CoreImage.CIFilterBuiltins

/// A raster basemap drawn instead of Apple's.
///
/// Tiles load through `TileCache.session` — a plain URLSession whose only
/// addition is a large disk cache, so ground already seen never downloads
/// again. Anything more proved harmful: an earlier version stacked a
/// connection cap and retries on top and tiles stopped arriving, while the
/// actual culprit was MapKit properties being rewritten on every view update.
///
/// Apple's basemap is deliberately left drawing underneath
/// (`canReplaceMapContent` stays false). With it suppressed, any tile not yet
/// on screen showed as bare black, and zooming flashed black across the map on
/// every level change — even over ground already cached, because there is
/// always a moment between MapKit asking for a tile and drawing it. Apple's
/// muted plan underneath turns that moment into a brief glimpse of a map
/// instead of a hole.
///
/// Both providers serve opaque tiles, so the basemap is invisible once they
/// land; the cost is only that MapKit keeps rendering a layer that is then
/// covered.
final class RasterTileOverlay: MKTileOverlay {
    /// De 0 à 1 : à quel point chaque tuile est assombrie, 0 la laissant
    /// telle quelle. Voir `darkened(_:level:)`.
    let darkLevel: Double
    /// La teinte de la carte de nuit — voir `MapNightTint`.
    let tint: MapNightTint
    var darkened: Bool { darkLevel > 0 }

    /// La carte globale : sept cents traces par-dessus, le fond doit se taire.
    let muted: Bool

    init(
        source: TileSource, darkLevel: Double = 0, tint: MapNightTint = .green,
        muted: Bool = false
    ) {
        self.darkLevel = darkLevel
        self.tint = tint
        self.muted = muted
        super.init(urlTemplate: source.urlTemplate)
        canReplaceMapContent = false
        minimumZ = 2
        maximumZ = source.maximumZ
    }

    /// Routed through the cached session; MapKit's own loader keeps nothing on
    /// disk, so panning back over the same ground re-fetched every tile.
    ///
    /// The response is checked rather than trusted. A WMTS service answers a
    /// refused or malformed request with `200 OK` and an XML exception in the
    /// body, and handing that to MapKit as a tile leaves a hole it papers over by
    /// stretching the parent zoom level across it. Worse, the session's policy is
    /// `returnCacheDataElseLoad` — a cached answer is reused whatever its age — so
    /// one such response would keep that patch of map wrong for good, whichever
    /// way you panned. Hence the eviction before throwing: MapKit asks again
    /// later, and next time it may well work.
    /// Appelé sur le fil principal quand plus aucune dalle n'est en cours de
    /// chargement — après au moins une. Une fois, puis oublié.
    @MainActor var onIdle: (() -> Void)?

    private let inFlight = NSLock()
    nonisolated(unsafe) private var pending = 0

    override func loadTile(at path: MKTileOverlayPath) async throws -> Data {
        inFlight.withLock { pending += 1 }
        defer {
            let idle = inFlight.withLock { pending -= 1; return pending == 0 }
            if idle { Task { @MainActor in self.settle() } }
        }
        return try await fetchTile(at: path)
    }

    /// Calme confirmé un instant plus tard : des dalles servies depuis la
    /// mémoire reviennent une à une, chacune laissant croire au calme.
    @MainActor private func settle() {
        guard onIdle != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            guard inFlight.withLock({ pending == 0 }), let done = onIdle else { return }
            onIdle = nil
            done()
        }
    }

    private func fetchTile(at path: MKTileOverlayPath) async throws -> Data {
        let key = "\(path.z)/\(path.x)/\(path.y)/\(urlTemplate ?? "")/\(darkLevel)/\(tint.rawValue)/\(muted)" as NSString
        // Avant tout aller-retour, même au cache disque : une tuile préchargée
        // pour un glissé doit tomber tout de suite.
        if darkened, let done = Self.processed.object(forKey: key) { return done as Data }
        let request = URLRequest(url: url(forTilePath: path))
        let (data, response) = try await TileCache.session.data(for: request)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, Self.looksLikeAnImage(data) else {
            TileCache.session.configuration.urlCache?
                .removeCachedResponse(for: request)
            throw TileLoadError.notAnImage(status: status, bytes: data.count)
        }
        guard darkened else { return data }
        let result = Self.darkened(data, level: darkLevel, tint: tint, muted: muted) ?? data
        Self.processed.setObject(result as NSData, forKey: key, cost: result.count)
        return result
    }

    /// Charge d'avance les tuiles d'un cadrage à venir, pour qu'elles soient
    /// prêtes — en cache disque, et déjà assombries la nuit — quand MapKit
    /// les demandera à l'arrivée d'un glissé.
    ///
    /// Le niveau que MapKit choisira n'est pas connu au point près : les deux
    /// qui encadrent l'échelle visée, au facteur d'écran près. Plafonné, pour
    /// qu'un cadrage immense ne lance pas des centaines de requêtes.
    func prefetch(_ rect: MKMapRect, viewWidth: CGFloat, scale: CGFloat) {
        guard viewWidth > 0, rect.width > 0 else { return }
        // En points, pas en pixels : relevé à l'usage, MapKit demande sur un
        // écran Retina le niveau des points, en tuiles de facteur 2.
        let ideal = log2(MKMapRect.world.width * Double(viewWidth) / rect.width / 256)
        let levels = Set([Int(ideal.rounded(.down)), Int(ideal.rounded(.up))])
            .map { min(max($0, minimumZ), maximumZ) }
        var paths: [MKTileOverlayPath] = []
        for z in Set(levels) {
            let tiles = Double(1 << z)
            let span = MKMapRect.world.width / tiles
            let x0 = max(0, Int(rect.minX / span)), x1 = min(Int(tiles) - 1, Int(rect.maxX / span))
            let y0 = max(0, Int(rect.minY / span)), y1 = min(Int(tiles) - 1, Int(rect.maxY / span))
            guard x0 <= x1, y0 <= y1 else { continue }
            for x in x0...x1 {
                for y in y0...y1 {
                    paths.append(MKTileOverlayPath(x: x, y: y, z: z, contentScaleFactor: scale))
                }
            }
        }
        guard paths.count <= 200 else { return }
        // La variante à rappel du même `loadTile` : c'est la surcharge
        // ci-dessous qui répond, cache et assombrissement compris.
        for path in paths {
            loadTile(at: path) { _, _ in }
        }
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Les tuiles de nuit déjà faites, en mémoire. Le disque garde la tuile
    /// d'origine ; la refaire en négatif à chaque passage coûtait un rendu et
    /// un encodage par tuile, et revenir sur une sortie du même secteur — le
    /// cas courant — les refaisait toutes. Plafonné à 64 Mo.
    nonisolated(unsafe) private static let processed: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// Une carte de nuit fabriquée à partir de celle de jour.
    ///
    /// Ni l'IGN ni OpenTopoMap ne servent de tuiles sombres — les capacités de
    /// la Géoplateforme n'en listent aucune —, et une carte papier en plein
    /// mode sombre éblouissait au milieu du volet. Le négatif fait le fond
    /// noir et le texte blanc ; une rotation de teinte d'un demi-tour rend
    /// ensuite aux couleurs leur sens — l'eau bleue, les forêts vertes, les
    /// routes jaunes — que le négatif seul avait inversées. Contraste et
    /// luminosité baissent ensuite avec `level`, réglé dans les préférences :
    /// à 0,5, le fond du papier tombe vers un gris presque noir, et les
    /// blancs du texte ne crient plus.
    ///
    /// Fait à la volée, sur la tuile déjà en cache : le disque garde l'image
    /// d'origine, et repasser au mode clair ne télécharge rien.
    static func darkened(
        _ data: Data, level: Double, tint: MapNightTint = .neutral, muted: Bool = false
    ) -> Data? {
        guard let input = CIImage(data: data) else { return nil }
        let invert = CIFilter.colorInvert()
        invert.inputImage = input
        let hue = CIFilter.hueAdjust()
        hue.inputImage = invert.outputImage
        hue.angle = .pi
        let controls = CIFilter.colorControls()
        controls.inputImage = hue.outputImage
        let level = Float(min(max(level, 0), 1))
        controls.contrast = 0.9 - 0.3 * level
        controls.brightness = -0.02 - 0.2 * level
        // Moins de couleur que de jour : le fond sert la trace, et ses bleus
        // et ses jaunes vifs lui disputaient le regard.
        controls.saturation = 0.7 - 0.2 * level
        // Sur la carte globale, beaucoup plus effacé encore, comme Plans y est
        // mis en sourdine : le relief inversé y faisait des taches claires,
        // routes et rivières des traits vifs, et sept cents traces fines s'y
        // perdaient — « avec Plan les traces sont bien visibles, pas avec
        // notre version », captures côte à côte.
        if muted {
            // Le contraste rabattu seul éclaircissait le tout — il pivote
            // autour du gris moyen — : la luminosité descend d'autant.
            controls.contrast *= 0.7
            controls.brightness -= 0.22
            controls.saturation *= 0.5
        }
        var tinted = controls.outputImage
        if let (scale, bias) = tint.matrix {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = tinted
            matrix.rVector = CIVector(x: scale.r, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: scale.g, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: scale.b, w: 0)
            matrix.biasVector = CIVector(x: bias.r, y: bias.g, z: bias.b, w: 0)
            tinted = matrix.outputImage
        }
        guard let output = tinted,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        // En JPEG plutôt qu'en PNG : la tuile est opaque, et l'encodage est
        // plusieurs fois plus rapide — c'est lui qui retardait l'apparition
        // de chaque tuile de nuit.
        return context.jpegRepresentation(
            of: output.cropped(to: input.extent), colorSpace: space,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
        )
    }

    /// Whether a payload starts like an image both providers actually serve.
    ///
    /// Magic bytes rather than the `Content-Type` header, which is exactly what
    /// lies in this situation: a WMTS exception is served as `image/png` by more
    /// than one implementation.
    static func looksLikeAnImage(_ data: Data) -> Bool {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF]
        return data.starts(with: png) || data.starts(with: jpeg)
    }
}

enum TileLoadError: Error {
    case notAnImage(status: Int, bytes: Int)
}

/// What a map view has already been told, so it is not told again.
struct MapStyleState {
    var applied: MapStyle?
    /// L'assombrissement des tuiles à la dernière pose — 0 en mode clair —
    /// et leur teinte : les tuiles topographiques se refont quand l'un change.
    var darkLevel: Double?
    var tint: MapNightTint?
    var topoOverlay: MKTileOverlay?
}

extension MKMapView {
    /// Where the raster basemap sits, and therefore where tracks must sit too.
    ///
    /// Above Apple's labels, because those draw above roads: at `.aboveRoads`
    /// the tiles left every village named twice, once by the raster and once by
    /// the basemap showing through underneath.
    static let rasterLevel: MKOverlayLevel = .aboveLabels

    /// Adds track overlays above the raster layer.
    ///
    /// Not `addOverlay(_:)`: the MapKit header states that it "operates
    /// implicitly on overlays in MKOverlayLevelAboveRoads", a level *below* the
    /// raster tiles. A track added that way is drawn first and then painted over
    /// the instant the tiles arrive — it flashed into view with Apple's basemap
    /// and disappeared under the topographic layer.
    func addTrackOverlays(_ overlays: [any MKOverlay]) {
        addOverlays(overlays, level: Self.rasterLevel)
    }

    /// Applies a style, adding, swapping or removing the raster layer as needed.
    ///
    /// Everything is gated on a real style change: reassigning
    /// `preferredConfiguration` makes MapKit reload its basemap and drop
    /// whatever the tile overlay had already rendered, and this runs on every
    /// SwiftUI update — including every mouse move while a chart is hovered.
    ///
    /// The camera is deliberately left alone. An earlier version pinned it flat
    /// under the raster layers, on the mistaken theory that MapKit would not
    /// draw a tile overlay in a pitched view; pitch and rotation work fine.
    ///
    /// `mutesTiles` fait de même pour les fonds topographiques de nuit seulement
    /// — la carte d'une fiche le demande sans vouloir pour autant d'un Plan
    /// éteint. Par défaut, il suit `muted`.
    ///
    /// `muted` greys Apple's plan down, for a map whose point is what is drawn
    /// on it — the global map, where the saturated green relief fought seven
    /// hundred coloured tracks.
    func apply(
        _ style: MapStyle, state: inout MapStyleState, muted: Bool = false,
        mutesTiles: Bool? = nil,
        dark: Bool = NSApp.effectiveAppearance.isDark,
        darkLevel: Double = MapStyle.storedDarkLevel,
        tint: MapNightTint = MapNightTint.stored
    ) {
        let level = dark ? darkLevel : 0
        guard state.applied != style || state.darkLevel != level || state.tint != tint
        else { return }
        state.applied = style
        state.darkLevel = level
        state.tint = tint

        if muted, style == .standard {
            preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .realistic, emphasisStyle: .muted
            )
        } else {
            preferredConfiguration = style.configuration
        }

        // Both topographic providers serve paper-toned tiles whatever the system
        // appearance — there is no night PLAN IGN, the Géoplateforme
        // capabilities list none — so in dark mode Apple's dark basemap showed
        // through as a dark hole during a zoom. Pinning this map view to a light
        // appearance makes that moment match the tiles. Back to inheriting for
        // Apple's own styles, which do have a proper dark map.
        //
        // Depuis que les tuiles passent en négatif la nuit, la carte d'Apple
        // dessous suit : sombre sous des tuiles sombres.
        appearance = style.tileSource == nil
            ? nil : NSAppearance(named: level > 0 ? .darkAqua : .aqua)

        // The old layer goes first even when the new style is also tiled: IGN
        // and OpenTopoMap are different sources, and keeping whichever was
        // there would silently ignore the switch.
        if let existing = state.topoOverlay {
            removeOverlay(existing)
            state.topoOverlay = nil
        }
        if let source = style.tileSource {
            let tiles = RasterTileOverlay(
                source: source, darkLevel: level, tint: tint, muted: mutesTiles ?? muted
            )
            // At index 0 of the level, so the tracks added after it stay on top.
            insertOverlay(tiles, at: 0, level: Self.rasterLevel)
            state.topoOverlay = tiles
            // Switching to a raster layer straightens the camera, including a
            // tilt set by hand: see `flattenCamera` for why the two cannot share
            // a view.
            flattenCamera()
        }
    }
}

extension MKMapView {
    /// Le fond de tuiles, que les vues gardent quand elles redessinent leurs
    /// traces.
    static func isBasemap(_ overlay: any MKOverlay) -> Bool {
        overlay is MKTileOverlay
    }

    /// Le rendu du fond, ou nil pour une trace.
    static func basemapRenderer(for overlay: any MKOverlay) -> MKOverlayRenderer? {
        if let tiles = overlay as? MKTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tiles)
        }
        return nil
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// La teinte des cartes topographiques de nuit.
///
/// Neutre, le négatif donne un fond gris presque noir. Vert, il rejoint le
/// mode sombre de Plans, où un fond vert-de-gris laisse mieux ressortir une
/// trace de couleur — préféré le 1er octobre 2026, capture de Plans à
/// l'appui.
enum MapNightTint: String, CaseIterable, Identifiable, Sendable {
    case green
    case neutral

    var id: String { rawValue }
    static let storageKey = "mapNightTint"
    static var stored: MapNightTint {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MapNightTint.init) ?? .green
    }

    var displayName: String {
        switch self {
        case .green: "Vert, comme Plans"
        case .neutral: "Gris neutre"
        }
    }

    /// Le gain et le décalage de chaque canal : le rouge baisse, le vert et
    /// un peu le bleu montent dans les sombres. Réglé sur une tuile IGN de
    /// Sury-le-Comtal, à côté du mode sombre de Plans.
    fileprivate var matrix: (
        scale: (r: CGFloat, g: CGFloat, b: CGFloat), bias: (r: CGFloat, g: CGFloat, b: CGFloat)
    )? {
        switch self {
        case .neutral: nil
        case .green: ((0.72, 0.92, 0.80), (0.03, 0.10, 0.07))
        }
    }
}

/// Ses réglages sont fixés à la création, le compte des dalles en cours est
/// sous verrou et `onIdle` reste sur le fil principal.
extension RasterTileOverlay: @unchecked Sendable {}
