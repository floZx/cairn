import SwiftUI

/// The shape of a track, small enough to sit in a row.
///
/// No MapKit: a map view per row would be hundreds of tile requests and a
/// renderer each. The simplified track already in the row is enough to
/// recognise an outing — a loop, an out-and-back, a figure of eight are all
/// distinguishable at forty points and forty pixels.
struct TrackThumbnail: View {
    let coordinates: [Coordinate]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let points = Self.points(
                for: coordinates, in: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            )
            guard points.count > 1 else { return }

            var path = Path()
            path.addLines(points)
            context.stroke(
                path, with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }

    /// Fits a track into `rect`, keeping its proportions.
    ///
    /// Longitude is scaled by the cosine of the latitude before anything else:
    /// a degree of longitude is only about 70 % of a degree of latitude in
    /// France, so plotting the two on the same scale stretches every track
    /// sideways and turns a round loop into an oval.
    ///
    /// The aspect ratio is then preserved and the result centred, because the
    /// point of the thumbnail is the *shape*: a track squashed to fill the box
    /// says nothing about the outing it came from.
    static func points(for coordinates: [Coordinate], in rect: CGRect) -> [CGPoint] {
        guard coordinates.count > 1, rect.width > 0, rect.height > 0 else { return [] }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max()
        else { return [] }

        let scale = cos((minLat + maxLat) / 2 * .pi / 180)
        let spanX = max((maxLon - minLon) * scale, .leastNonzeroMagnitude)
        let spanY = max(maxLat - minLat, .leastNonzeroMagnitude)
        // The smaller ratio is what fits: taking the larger would crop the track.
        let unit = min(rect.width / spanX, rect.height / spanY)

        let offsetX = rect.minX + (rect.width - spanX * unit) / 2
        let offsetY = rect.minY + (rect.height - spanY * unit) / 2

        return coordinates.map { coordinate in
            CGPoint(
                x: offsetX + (coordinate.longitude - minLon) * scale * unit,
                // Latitude grows northwards and y grows downwards, so the track
                // would otherwise come out upside down.
                y: offsetY + (maxLat - coordinate.latitude) * unit
            )
        }
    }
}
