import MapKit

extension MKMapView {
    /// How far the camera leans over the terrain on an activity's map.
    ///
    /// A frank tilt, but not the maximum: the steeper the angle, the further the
    /// camera has to pull back to keep the whole route in frame, and past roughly
    /// 50° the track is so small that the relief it was meant to show is lost
    /// with it. MapKit clamps this further according to the altitude, so the
    /// effective tilt is gentler when zoomed far out.
    static let terrainPitch: CGFloat = 45

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
        // Leaning back stretches what has to fit vertically by 1/cos(pitch).
        // Pull back by less than that and the near half of the track slides off
        // the bottom edge — at 70° with a flat 1.35 factor the route vanished
        // from the view altogether.
        camera.centerCoordinateDistance =
            distance / cos(Self.terrainPitch * .pi / 180)
        self.camera = camera
    }
}
