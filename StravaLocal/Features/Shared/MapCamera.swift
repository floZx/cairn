import MapKit

extension MKMapView {
    /// How far the camera leans over the terrain on an activity's map.
    ///
    /// A request, not a result: MapKit clamps pitch according to the altitude and
    /// the map configuration, and says nothing about it. Measured on a framed
    /// track it granted roughly 35° for a requested 55 or 62, so the effective
    /// tilt is MapKit's call and asking high simply means "as much as you allow".
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
    /// `updateNSView` the map view has no size, `centerCoordinateDistance` reads
    /// zero and there is nothing to lean. Diagnostics caught that as
    /// `skipped: distance=0.0` — a single line, since the caller had already
    /// recorded the track as drawn and never came back. Callers therefore keep
    /// asking until it returns true; `mapViewDidChangeVisibleRegion` is when the
    /// geometry finally exists.
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
        guard frame.width > 0, distance > 0 else {
            Diagnostics.camera(
                "not yet: distance=\(distance) frame=\(Int(frame.width))x\(Int(frame.height))"
            )
            return false
        }
        // Already leaning — by hand, most likely. Left as it is: overruling it on
        // every activity change would undo the gesture the user just made.
        guard current.pitch < 1 else {
            Diagnostics.camera("kept manual pitch=\(current.pitch)")
            return true
        }

        setCamera(
            MKMapCamera(
                lookingAtCenter: current.centerCoordinate,
                fromDistance: distance * Self.pitchedDistanceFactor,
                pitch: Self.terrainPitch,
                heading: current.heading
            ),
            animated: false
        )
        Diagnostics.camera(
            "asked pitch=\(Self.terrainPitch) distance=\(Int(distance)) "
                + "-> got pitch=\(camera.pitch) distance=\(Int(camera.centerCoordinateDistance)) "
                + "frame=\(Int(frame.width))x\(Int(frame.height))"
        )
        return true
    }
}
