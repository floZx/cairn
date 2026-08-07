import MapKit

extension MKMapView {
    /// How far the camera leans over the terrain on a track map.
    ///
    /// High on purpose — the relief is the point. MapKit clamps this according
    /// to the altitude and the configuration, so the effective tilt is gentler
    /// when zoomed far out; that is its own doing, not a second rule here.
    static let terrainPitch: CGFloat = 70

    /// Leaning back raises the far edge of the frame towards the horizon, which
    /// would otherwise crop the top of the track. Pulling the camera back keeps
    /// the whole route inside the view.
    private static let pitchedDistanceFactor = 1.35

    /// Tilts the camera into a terrain view, keeping what is already framed.
    ///
    /// Call it straight after setting the visible map rect, and only there: on
    /// every update it would snap the camera back each time the view refreshed,
    /// undoing any tilt or rotation the user had set with option-drag. Note that
    /// it pulls the camera back each time, so repeated calls would keep zooming
    /// out.
    func tiltForTerrain() {
        let camera = self.camera
        camera.pitch = Self.terrainPitch
        camera.centerCoordinateDistance *= Self.pitchedDistanceFactor
        self.camera = camera
    }
}
