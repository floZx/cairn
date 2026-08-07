import MapKit

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
    init(source: TileSource) {
        super.init(urlTemplate: source.urlTemplate)
        canReplaceMapContent = false
        minimumZ = 2
        maximumZ = source.maximumZ
    }

    /// Routed through the cached session; MapKit's own loader keeps nothing on
    /// disk, so panning back over the same ground re-fetched every tile.
    override func loadTile(at path: MKTileOverlayPath) async throws -> Data {
        let (data, _) = try await TileCache.session.data(
            for: URLRequest(url: url(forTilePath: path))
        )
        return data
    }
}

/// What a map view has already been told, so it is not told again.
struct MapStyleState {
    var applied: MapStyle?
    var topoOverlay: MKTileOverlay?
}

extension MKMapView {
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
    func apply(_ style: MapStyle, state: inout MapStyleState) {
        guard state.applied != style else { return }
        state.applied = style

        preferredConfiguration = style.configuration

        // Both topographic providers serve paper-toned tiles whatever the system
        // appearance — there is no night PLAN IGN, the Géoplateforme
        // capabilities list none — so in dark mode Apple's dark basemap showed
        // through as a dark hole during a zoom. Pinning this map view to a light
        // appearance makes that moment match the tiles. Back to inheriting for
        // Apple's own styles, which do have a proper dark map.
        appearance = style.tileSource == nil ? nil : NSAppearance(named: .aqua)

        // The old layer goes first even when the new style is also tiled: IGN
        // and OpenTopoMap are different sources, and keeping whichever was
        // there would silently ignore the switch.
        if let existing = state.topoOverlay {
            removeOverlay(existing)
            state.topoOverlay = nil
        }
        if let source = style.tileSource {
            let tiles = RasterTileOverlay(source: source)
            insertOverlay(tiles, at: 0, level: .aboveRoads)
            state.topoOverlay = tiles
        }
    }
}
