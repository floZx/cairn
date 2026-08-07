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
        #expect(MapStyle.relief.tileSource == nil)
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
}
