import MapKit

extension MKMapView {
    /// How far the camera leans over the terrain on an activity's map.
    ///
    /// Deliberately steep — the relief is the point. MapKit clamps the angle
    /// further according to the altitude, so the effective tilt is gentler when
    /// zoomed far out.
    static let terrainPitch: CGFloat = 70

    /// A small margin so the near end of the track does not sit against the
    /// bottom edge once the camera leans over.
    ///
    /// Empirical, and modest on purpose. A first version derived it as
    /// 1/cos(pitch) — nearly three times the distance at 70° — which framed the
    /// route so far off that it had to be zoomed back in by hand. That
    /// derivation had the effect backwards: a tilted camera sees *more* ground,
    /// not less, because everything beyond the centre compresses towards the
    /// horizon. Only the near half needs any room at all.
    private static let pitchedDistanceFactor = 1.15

    /// Tilts the camera into a terrain view, keeping what is already framed.
    ///
    /// Call it straight after setting the visible map rect, and only there: on
    /// every update it would snap the camera back each time the view refreshed,
    /// undoing any tilt or rotation the user had set with option-drag. It pulls
    /// the camera back each time, so repeated calls would keep zooming out.
    func tiltForTerrain() {
        let distance = camera.centerCoordinateDistance
        // A camera can be degenerate before the view has been laid out, and
        // scaling zero or a negative distance would send the map elsewhere
        // entirely rather than merely mis-framing it.
        guard distance > 0 else { return }

        let camera = self.camera
        camera.pitch = Self.terrainPitch
        camera.centerCoordinateDistance = distance * Self.pitchedDistanceFactor
        self.camera = camera
    }
}
