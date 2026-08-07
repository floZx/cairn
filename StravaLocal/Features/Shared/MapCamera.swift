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
    /// Call it straight after setting the visible map rect, and only there: on
    /// every update it would snap the camera back each time the view refreshed.
    ///
    /// Two things this gets right that an earlier version did not. It builds a
    /// *new* `MKMapCamera` — the `camera` getter hands back the view's live
    /// object, so mutating that and assigning it back is asking MapKit to replace
    /// a camera with itself. And it leaves an already-tilted camera alone, so a
    /// tilt set by hand with option-drag survives changing activity.
    func tiltForTerrain() {
        let current = camera
        let distance = current.centerCoordinateDistance
        // A camera can be degenerate before the view has been laid out, and
        // scaling zero or a negative distance would send the map elsewhere
        // entirely rather than merely mis-framing it.
        guard distance > 0 else {
            Diagnostics.camera("skipped: distance=\(distance)")
            return
        }
        // Already leaning — by hand, most likely. Left as it is: overruling it on
        // every activity change would undo the gesture the user just made.
        guard current.pitch < 1 else {
            Diagnostics.camera("kept manual pitch=\(current.pitch)")
            return
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
    }
}
