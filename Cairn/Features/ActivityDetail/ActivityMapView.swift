import SwiftUI
import MapKit

/// Single-track map, with an optional point highlighted along the way.
///
/// Uses MKMapView rather than SwiftUI's `Map` because the global map needs
/// MKMapView anyway, and sharing the renderer keeps the two maps looking
/// identical.
struct ActivityMapView: NSViewRepresentable {
    /// Lu pour que le passage en mode sombre redessine les tuiles
    /// topographiques — voir `RasterTileOverlay.darkened`.
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MapStyle.darkLevelKey) private var darkLevel = MapStyle.defaultDarkLevel
    @AppStorage(MapNightTint.storageKey) private var nightTint: MapNightTint = .green
    let coordinates: [Coordinate]
    /// Follows the cursor over the charts. Updating it must not disturb the
    /// map's framing, which is why the track is only rebuilt when it changes.
    var highlight: Coordinate?
    /// La portion choisie sur le profil d'altitude, tracée par-dessus la trace.
    var segment: [Coordinate] = []
    var style: MapStyle = .standard
    var trackColor: TrackColor = .accent

    func makeNSView(context: Context) -> MKMapView {
        let mapView = CursorAssertingMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsZoomControls = true
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        // Fond topo de nuit effacé comme sur la carte globale : la trace passe
        // devant — demandé après l'avoir vu là-bas.
        mapView.apply(
            style, state: &coordinator.mapStyleState, mutesTiles: true,
            dark: colorScheme == .dark, darkLevel: darkLevel, tint: nightTint
        )

        var hasher = Hasher()
        hasher.combine(coordinates.count)
        hasher.combine(coordinates.first)
        hasher.combine(coordinates.last)
        // In the signature so changing the colour redraws: MapKit keeps its
        // renderers, and a new stroke colour alone would not reach the screen.
        hasher.combine(trackColor)
        // Le fond topo appelle une trace plus épaisse et soulignée : la
        // changer de fond doit la redessiner.
        let onRaster = style.tileSource != nil
        hasher.combine(onRaster)
        let signature = hasher.finalize()

        // Rebuilding and re-framing on every update would fight the user's own
        // zoom, and would snap the map on every mouse move once a chart is
        // being hovered.
        if coordinator.renderedSignature != signature {
            coordinator.renderedSignature = signature
            coordinator.trackColor = trackColor
            coordinator.onRaster = onRaster
            mapView.removeOverlays(
                mapView.overlays.filter { !MKMapView.isBasemap($0) }
            )
            mapView.removeAnnotations(mapView.annotations)
            coordinator.marker = nil
            coordinator.segmentOverlays = []
            coordinator.segmentSignature = nil

            guard coordinates.count > 1 else { return }
            let polyline = MKPolyline(
                coordinates: coordinates.map(\.clLocation), count: coordinates.count
            )
            // Sur un fond topographique, un liseré sombre sous la trace : les
            // routes, l'eau et les courbes de niveau y sont de la même famille
            // de couleurs qu'elle, et elle s'y perdait — « la trace ne ressort
            // pas », signalé, capture du mode sombre à l'appui.
            if onRaster {
                let points = coordinates.map(\.clLocation)
                mapView.addTrackOverlays([TrackCasing(coordinates: points, count: points.count)])
            }
            mapView.addTrackOverlays([polyline])
            if let first = coordinates.first {
                let start = StartAnnotation()
                start.coordinate = first.clLocation
                start.color = trackColor.nsColor
                mapView.addAnnotation(start)
            }
            // D'une sortie à l'autre dans le même coin, la caméra glisse
            // jusqu'à la nouvelle trace au lieu de sauter : les tuiles du
            // secteur sont déjà là, et l'œil suit le passage. Un saut net
            // reste de mise loin d'ici — un vol au-dessus de la France
            // chargerait tout le trajet — et au premier cadrage.
            let target = polyline.boundingMapRect
            let padding = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
            // Le cadrage d'arrivée tel que la vue le montrera, et non la trace
            // brute : une trace étroite dans une vue large semblait huit fois
            // plus petite que le cadre d'une trace large, et le glissé
            // sautait — du 27 au 26 septembre, pas dans l'autre sens.
            let nearby = coordinator.hasFramed && mapView.bounds.width > 0
                && Self.isNearby(
                    mapView.mapRectThatFits(target, edgePadding: padding),
                    mapView.visibleMapRect
                )
            // Une carte neuve sur un fond topo reste cachée le temps que ses
            // premières dalles arrivent, puis apparaît en fondu : sans quoi
            // Plans s'affichait d'abord, puis l'IGN par-dessus, dalle après
            // dalle — « perturbant ». MapKit dessine son fond avant tout
            // calque posé dessus, un aplat sous les dalles n'y changeait rien.
            if !coordinator.hasFramed,
               let tiles = coordinator.mapStyleState.topoOverlay as? RasterTileOverlay {
                coordinator.revealWhenLoaded(mapView, tiles: tiles)
            }
            coordinator.hasFramed = true
            // En 3D, le glissé passe par la caméra — inclinaison comprise — :
            // un cadrage animé sous une caméra penchée perdait parfois la
            // trace, « en Plan, parfois la trace ne s'affiche pas ».
            // Les tuiles de l'arrivée sont demandées dès le départ : le temps
            // du glissé, elles ont le temps d'arriver, et l'IGN se pose sans
            // que Plan transparaisse d'abord.
            if let tiles = coordinator.mapStyleState.topoOverlay as? RasterTileOverlay {
                tiles.prefetch(
                    mapView.mapRectThatFits(target, edgePadding: padding),
                    viewWidth: mapView.bounds.width,
                    scale: mapView.window?.backingScaleFactor ?? 2
                )
            }
            if nearby, let ratio = coordinator.flatRatio,
               mapView.glide(to: target, edgePadding: padding, flatRatio: ratio) {
                coordinator.wantsTilt = false
            } else {
                mapView.setVisibleMapRect(target, edgePadding: padding, animated: false)
                if let ratio = mapView.flatDistanceRatio() { coordinator.flatRatio = ratio }
                // Apple's backgrounds only. Asked for now and, if the view has no
                // geometry yet, again from the delegate below.
                coordinator.wantsTilt = style.rendersInThreeDimensions
                    && !mapView.tiltForTerrain()
            }
        }

        coordinator.showSegment(segment, on: mapView)

        // The marker is an annotation whose coordinate is moved in place, not an
        // overlay torn down and rebuilt: removing and re-adding an overlay on
        // every mouse move makes the marker stutter across the track.
        guard let highlight else {
            if let marker = coordinator.marker {
                mapView.removeAnnotation(marker)
                coordinator.marker = nil
            }
            return
        }

        if let marker = coordinator.marker {
            marker.coordinate = highlight.clLocation
        } else {
            let marker = HoverAnnotation()
            marker.coordinate = highlight.clLocation
            mapView.addAnnotation(marker)
            coordinator.marker = marker
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Si deux cadrages sont assez proches pour qu'un glissé de l'un à
    /// l'autre reste un geste court : centres à moins de trois fois la taille
    /// de la vue actuelle, et une échelle qui ne change pas de plus d'un
    /// facteur huit.
    static func isNearby(_ target: MKMapRect, _ current: MKMapRect) -> Bool {
        guard !current.isNull, !current.isEmpty, !target.isNull else { return false }
        let span = max(current.width, current.height)
        let dx = target.midX - current.midX, dy = target.midY - current.midY
        let distance = (dx * dx + dy * dy).squareRoot()
        let scale = max(target.width, target.height) / span
        return distance < 3 * span && scale > 1 / 8 && scale < 8
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderedSignature: Int?
        /// Vrai une fois une trace cadrée : la suivante peut y glisser.
        var hasFramed = false
        /// Relevé au dernier cadrage à plat : voir `flatDistanceRatio`.
        var flatRatio: Double?
        var marker: HoverAnnotation?
        var mapStyleState = MapStyleState()
        var trackColor: TrackColor = .accent
        /// Vrai sur un fond IGN ou OpenTopoMap : trace plus épaisse, liseré
        /// dessous.
        var onRaster = false
        /// A tilt still owed, because the view had no geometry when it was framed.
        var wantsTilt = false

        private static let markerIdentifier = "hover"

        var segmentOverlays: [MKPolyline] = []
        var segmentSignature: Int?

        /// Redessine la portion sélectionnée quand elle change, et seulement
        /// alors : la mise à jour tombe à chaque mouvement de souris.
        ///
        /// Deux traits l'un sur l'autre — un liseré blanc, puis une couleur qui
        /// tranche sur la trace, deux fois plus épais qu'elle — : la portion
        /// ressort sur n'importe quel fond.
        /// Orange sur une trace bleue, violette ou noire ; bleu sur une trace
        /// déjà chaude. Dans la couleur de la trace, la portion se perdait :
        /// « bleu sur bleu », signalé.
        static func selectionColor(against track: TrackColor) -> NSColor {
            switch track {
            case .orange, .red: .systemBlue
            default: .systemOrange
            }
        }

        func showSegment(_ segment: [Coordinate], on mapView: MKMapView) {
            var hasher = Hasher()
            hasher.combine(segment.count)
            hasher.combine(segment.first)
            hasher.combine(segment.last)
            let signature = segment.count > 1 ? hasher.finalize() : nil
            guard signature != segmentSignature else { return }
            segmentSignature = signature
            mapView.removeOverlays(segmentOverlays)
            segmentOverlays = []
            guard segment.count > 1 else { return }
            let points = segment.map(\.clLocation)
            let halo = SelectionHalo(coordinates: points, count: points.count)
            let line = SelectionLine(coordinates: points, count: points.count)
            segmentOverlays = [halo, line]
            mapView.addTrackOverlays(segmentOverlays)
        }

        private var revealPending = false

        /// Masque la carte et la montre en fondu dès que ses dalles se sont
        /// posées — ou au bout d'une seconde et demie, quoi qu'il arrive.
        func revealWhenLoaded(_ mapView: MKMapView, tiles: RasterTileOverlay) {
            revealPending = true
            mapView.alphaValue = 0
            tiles.onIdle = { [weak self, weak mapView] in
                guard let mapView else { return }
                self?.reveal(mapView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak mapView] in
                guard let mapView else { return }
                self?.reveal(mapView)
            }
        }

        private func reveal(_ mapView: MKMapView) {
            guard revealPending else { return }
            revealPending = false
            // Le temps pour MapKit de peindre les dernières dalles reçues.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    mapView.animator().alphaValue = 1
                }
            }
        }

        /// Where a deferred tilt finally lands.
        ///
        /// `updateNSView` runs before SwiftUI has laid the map out, so the camera
        /// reports a zero distance and cannot be leaned. This fires once the
        /// region is real — the layout pass included. The flag is cleared before
        /// tilting, so the region change tilting itself causes is a no-op rather
        /// than a loop.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // Relevé à chaque mouvement à plat : sur un fond IGN, aucune
            // inclinaison n'est attendue, et le premier cadrage tombe avant que
            // la vue ait une taille — le glissé n'avait jamais de quoi viser.
            if let ratio = mapView.flatDistanceRatio() { flatRatio = ratio }
            guard wantsTilt, mapView.frame.width > 0 else { return }
            wantsTilt = false
            if !mapView.tiltForTerrain() { wantsTilt = true }
        }

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            if let basemap = MKMapView.basemapRenderer(for: overlay) {
                return basemap
            }
            if overlay is TrackCasing {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = NSColor.black.withAlphaComponent(0.6)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            if overlay is SelectionHalo {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = .white
                renderer.lineWidth = 8
                renderer.lineCap = .round
                return renderer
            }
            if overlay is SelectionLine {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = Self.selectionColor(against: trackColor)
                renderer.lineWidth = 5
                renderer.lineCap = .round
                return renderer
            }
            // Directed: chevrons along the line show which way it was run.
            let renderer = DirectedPolylineRenderer(overlay: overlay)
            renderer.strokeColor = trackColor.nsColor
            // Thin enough that the route's own shape stays readable, and that the
            // direction arrowheads stand out as barbs rather than bulges: at 4 the
            // stroke swallowed the switchbacks it was meant to show.
            renderer.lineWidth = onRaster ? 3.5 : 2
            return renderer
        }

        /// A plain dot rather than a pin: this marks a position along the trace,
        /// it is not a place the user can select.
        func mapView(
            _ mapView: MKMapView, viewFor annotation: any MKAnnotation
        ) -> MKAnnotationView? {
            if let start = mapView.startAnnotationView(for: annotation) {
                return start
            }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.markerIdentifier
            ) ?? MKAnnotationView(
                annotation: annotation, reuseIdentifier: Self.markerIdentifier
            )
            view.annotation = annotation
            view.canShowCallout = false
            view.isEnabled = false
            view.image = Self.dotImage
            return view
        }

        private static let dotImage: NSImage = {
            let diameter: CGFloat = 14
            let image = NSImage(
                size: NSSize(width: diameter, height: diameter), flipped: false
            ) { rect in
                let inset = rect.insetBy(dx: 2, dy: 2)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: inset).fill()
                NSColor.white.setStroke()
                let outline = NSBezierPath(ovalIn: inset)
                outline.lineWidth = 2
                outline.stroke()
                return true
            }
            return image
        }()
    }
}

/// Les deux traits de la portion sélectionnée, reconnus par leur classe dans
/// `rendererFor` : le liseré dessous, la ligne dessus.
final class SelectionHalo: MKPolyline {}
/// Le liseré sombre sous la trace, sur un fond topographique.
final class TrackCasing: MKPolyline {}
final class SelectionLine: MKPolyline {}
