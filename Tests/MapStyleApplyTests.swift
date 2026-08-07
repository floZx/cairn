import Testing
import MapKit
@testable import StravaLocal

@Suite("MapStyle.apply")
@MainActor
struct MapStyleApplyTests {
    @Test("changer de fond topographique remplace le calque de tuiles")
    func switchingTopoSourcesSwapsTheOverlay() {
        let mapView = MKMapView()
        var state = MapStyleState()

        mapView.apply(.ignTopo, state: &state)
        let first = state.topoOverlay
        #expect(first != nil)
        #expect(first?.urlTemplate?.contains("data.geopf.fr") == true)

        // The regression this pins: the old guard kept whichever overlay was
        // already there, so IGN tiles stayed on screen after picking OpenTopoMap.
        mapView.apply(.openTopo, state: &state)
        let second = state.topoOverlay
        #expect(second !== first)
        #expect(second?.urlTemplate?.contains("opentopomap.org") == true)
        #expect(mapView.overlays.count == 1)

        mapView.apply(.standard, state: &state)
        #expect(state.topoOverlay == nil)
        #expect(mapView.overlays.isEmpty)
    }

    @Test("réappliquer le même fond ne reconstruit rien")
    func reapplyingIsIdempotent() {
        let mapView = MKMapView()
        var state = MapStyleState()

        mapView.apply(.ignTopo, state: &state)
        let first = state.topoOverlay
        mapView.apply(.ignTopo, state: &state)

        #expect(state.topoOverlay === first)
        #expect(mapView.overlays.count == 1)
    }

    @Test("les fonds Apple n'ont pas de source de tuiles, les topo en ont une")
    func tileSourcesMatchStyles() {
        #expect(MapStyle.standard.tileSource == nil)
        #expect(MapStyle.satellite.tileSource == nil)
        #expect(MapStyle.hybrid.tileSource == nil)
        #expect(MapStyle.ignTopo.tileSource != nil)
        #expect(MapStyle.openTopo.tileSource != nil)
        // The templates carry the three placeholders MapKit substitutes.
        for style in [MapStyle.ignTopo, .openTopo] {
            let template = style.tileSource!.urlTemplate
            #expect(template.contains("{z}"))
            #expect(template.contains("{x}"))
            #expect(template.contains("{y}"))
        }
    }

    @Test("les fonds topo forcent l'apparence claire, les fonds Apple héritent")
    func pinsAppearanceForRasterStyles() {
        let mapView = MKMapView()
        var state = MapStyleState()

        // Paper-toned tiles with no dark variant: a dark basemap under them
        // shows as a dark hole while a zoom settles.
        mapView.apply(.ignTopo, state: &state)
        #expect(mapView.appearance?.name == .aqua)

        // Apple's own styles have a real dark map, so they follow the system.
        mapView.apply(.satellite, state: &state)
        #expect(mapView.appearance == nil)

        mapView.apply(.openTopo, state: &state)
        #expect(mapView.appearance?.name == .aqua)
    }

    @Test("le calque laisse le fond d'Apple dessous, sinon les zooms flashent")
    func keepsAppleBasemapUnderneath() {
        for style in [MapStyle.ignTopo, .openTopo] {
            let overlay = RasterTileOverlay(source: style.tileSource!)
            // Suppressing Apple's basemap left bare black wherever a tile was
            // not yet drawn, which meant a black flash on every zoom level
            // change — even over cached ground.
            #expect(overlay.canReplaceMapContent == false)
            #expect(overlay.maximumZ == style.tileSource!.maximumZ)
        }
    }

    @Test("tous les fonds rendent le relief, il n'y a plus de doublon")
    func everyStyleRendersTerrain() {
        // "Plan avec relief" is gone: with the plain plan now realistic too, the
        // two would have been the same map under two names.
        #expect(MapStyle.allCases.count == 5)
        #expect(MapStyle(rawValue: "relief") == nil)
        for style in MapStyle.allCases {
            let elevation = (style.configuration as? MKStandardMapConfiguration)?
                .elevationStyle
                ?? (style.configuration as? MKImageryMapConfiguration)?.elevationStyle
                ?? (style.configuration as? MKHybridMapConfiguration)?.elevationStyle
            #expect(elevation == .realistic)
        }
    }

    /// Only the single-activity map tilts: the global map and the comparison map
    /// are read from above, where a tilt would distort what they exist to show.
    @Test("la caméra s'incline sur le terrain et recule un peu")
    func tiltsTheCamera() {
        let mapView = MKMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        mapView.setVisibleMapRect(
            MKMapRect(x: 130_000_000, y: 90_000_000, width: 40_000, height: 40_000),
            animated: false
        )
        let distanceBefore = mapView.camera.centerCoordinateDistance

        mapView.tiltForTerrain()

        // MapKit clamps the pitch by altitude and says nothing about it, so the
        // angle obtained is its call — what matters is that it is no longer flat.
        #expect(mapView.camera.pitch > 0)
        // The pull-back stays a margin, not a zoom-out: a 1/cos(pitch) factor
        // framed the route so far off it had to be zoomed back in by hand.
        let distance = mapView.camera.centerCoordinateDistance
        #expect(distance > distanceBefore)
        #expect(distance < distanceBefore * 1.5)
    }

    @Test("sans géométrie, l'inclinaison est différée et non abandonnée")
    func reportsWhenItCannotTiltYet() {
        // A view with no size is exactly the state updateNSView runs in, and the
        // camera then reports a zero distance. Returning false is what tells the
        // caller to ask again from the delegate instead of giving up — the log
        // read "skipped: distance=0.0", once, and the map stayed flat for good.
        let unlaidOut = MKMapView()
        #expect(unlaidOut.tiltForTerrain() == false)

        let laidOut = MKMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        laidOut.setVisibleMapRect(
            MKMapRect(x: 130_000_000, y: 90_000_000, width: 40_000, height: 40_000),
            animated: false
        )
        #expect(laidOut.tiltForTerrain())
    }

    @Test("une inclinaison réglée à la main n'est pas écrasée")
    func leavesAManualTiltAlone() {
        let mapView = MKMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        mapView.setVisibleMapRect(
            MKMapRect(x: 130_000_000, y: 90_000_000, width: 40_000, height: 40_000),
            animated: false
        )
        // As option-drag would leave it. Read back rather than assumed: MapKit
        // clamps, so the starting point is whatever it granted.
        mapView.setCamera(
            MKMapCamera(
                lookingAtCenter: mapView.camera.centerCoordinate,
                fromDistance: mapView.camera.centerCoordinateDistance,
                pitch: 20,
                heading: 0
            ),
            animated: false
        )
        let manual = mapView.camera.pitch
        let distance = mapView.camera.centerCoordinateDistance
        #expect(manual > 0)

        mapView.tiltForTerrain()

        // Changing activity must not undo the gesture the user just made.
        #expect(mapView.camera.pitch == manual)
        #expect(mapView.camera.centerCoordinateDistance == distance)
    }
    @Test("la trace se dessine au-dessus des tuiles, jamais dessous")
    func tracksDrawAboveTheRasterLayer() {
        let mapView = MKMapView()
        var state = MapStyleState()
        mapView.apply(.ignTopo, state: &state)

        let track = MKPolyline(
            coordinates: [
                CLLocationCoordinate2D(latitude: 45.75, longitude: 4.83),
                CLLocationCoordinate2D(latitude: 45.76, longitude: 4.84),
            ],
            count: 2
        )
        mapView.addTrackOverlays([track])

        // addOverlay(_:) implicitly uses .aboveRoads, a level *below* the tiles,
        // which had the raster paint straight over the track the moment it
        // landed. Both must share the level, with the track added after.
        let layered = mapView.overlays(in: MKMapView.rasterLevel)
        #expect(layered.count == 2)
        #expect(layered.first is MKTileOverlay)
        #expect(layered.last === track)
        #expect(mapView.overlays(in: .aboveRoads).isEmpty)
    }
}
