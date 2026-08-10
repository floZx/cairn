import Testing
import AppKit
import MapKit
@testable import Cairn

@Suite("Calque de sélection sur la carte")
@MainActor
struct SelectionOverlayViewTests {
    @Test("le calque partage le repère de la carte qu'il recouvre")
    func sharesTheMapCoordinateSystem() {
        // Le rectangle est tracé dans le repère du calque puis converti en
        // coordonnées par la carte. Si les deux ne s'accordent pas sur le sens
        // de l'axe vertical, la zone filtrée est le miroir de celle qu'on voit.
        #expect(SelectionOverlayView().isFlipped == MKMapView().isFlipped)
    }
}
