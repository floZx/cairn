import MapKit

extension MKMapView {
    /// How far the camera leans over the terrain on an activity's map.
    ///
    /// A request, not a result: MapKit clamps pitch according to the altitude and
    /// says nothing about it. Measured on two real tracks in one session, the same
    /// requested 70° was granted in full on one and cut to 35° on the other, the
    /// closer framing getting less. Asking high therefore means "as much as you
    /// allow", and a short track leaning less than a long one is MapKit's call.
    static let terrainPitch: CGFloat = 70

    /// A small margin so the near end of the track does not sit against the
    /// bottom edge once the camera leans over.
    ///
    /// Empirical, and modest on purpose. A first version derived it as
    /// 1/cos(pitch) — nearly three times the distance at 70° — which framed the
    /// route so far off it had to be zoomed back in by hand. That derivation had
    /// the effect backwards: a tilted camera sees *more* ground, not less,
    /// because everything beyond the centre compresses towards the horizon.
    private static let pitchedDistanceFactor = 1.15

    /// Leans the camera over the terrain, keeping what is already framed.
    ///
    /// Returns whether it applied, because it often cannot yet: called from
    /// `updateNSView` the map view still has a zero frame and
    /// `centerCoordinateDistance` reads zero, so there is nothing to lean. An
    /// earlier version returned silently there, and since the caller had already
    /// recorded the track as drawn it never came back — the default tilt simply
    /// never happened. Callers now keep asking until this returns true;
    /// `mapViewDidChangeVisibleRegion` is when the geometry finally exists.
    ///
    /// Two further things this gets right that an earlier version did not. It
    /// builds a *new* `MKMapCamera` — the `camera` getter hands back the view's
    /// live object, so mutating that and assigning it back is asking MapKit to
    /// replace a camera with itself. And it leaves an already-tilted camera alone,
    /// so a tilt set by hand with option-drag survives changing activity.
    @discardableResult
    func tiltForTerrain() -> Bool {
        let current = camera
        let distance = current.centerCoordinateDistance
        // Both matter: a view with no size reports a zero distance, and scaling
        // zero would send the map elsewhere rather than merely mis-frame it.
        guard frame.width > 0, distance > 0 else { return false }
        // Already leaning — by hand, most likely. Left as it is: overruling it on
        // every activity change would undo the gesture the user just made.
        guard current.pitch < 1 else { return true }

        setCamera(
            MKMapCamera(
                lookingAtCenter: current.centerCoordinate,
                fromDistance: distance * Self.pitchedDistanceFactor,
                pitch: Self.terrainPitch,
                heading: current.heading
            ),
            animated: false
        )
        return true
    }

    /// Puts the camera flat, leaving the framing untouched.
    ///
    /// Applied when a third-party raster layer becomes active, and not as a
    /// precaution: MapKit gives such a layer a single zoom level for the whole
    /// visible rect, so a leaning camera stretches it — IGN tiles from two zoom
    /// levels in one image, with place names outsized in the distance. That
    /// includes a tilt the user set by hand before switching background, which is
    /// why this overrules it here and nowhere else.
    func flattenCamera() {
        let current = camera
        guard current.pitch > 0, current.centerCoordinateDistance > 0 else { return }
        setCamera(
            MKMapCamera(
                lookingAtCenter: current.centerCoordinate,
                fromDistance: current.centerCoordinateDistance,
                pitch: 0,
                heading: current.heading
            ),
            animated: false
        )
    }
}
