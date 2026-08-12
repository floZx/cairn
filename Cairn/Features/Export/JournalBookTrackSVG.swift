import Foundation
import SwiftUI

/// A track as a vector polyline, for a book made without a map.
///
/// The projection is `TrackThumbnail`'s, reached rather than copied: the shape
/// of an outing is recognisable at forty points, and that code already fits it,
/// centres it and corrects for a degree of longitude being shorter than a
/// degree of latitude. A second copy of that arithmetic would drift from the
/// one drawn on screen.
///
/// Vector rather than an image because a PDF keeps it sharp at any zoom, it
/// costs a few hundred bytes, and it needs neither network nor tiles — which is
/// exactly the situation it exists for.
///
/// On the main actor because the projection it borrows lives on a `View`, and
/// a `View`'s members are main-actor-isolated: calling it from anywhere else
/// traps at runtime rather than failing to build. The export pipeline runs
/// there anyway.
@MainActor
enum JournalBookTrackSVG {
    static func svg(
        for coordinates: [Coordinate], size: CGSize, hex: String
    ) -> String? {
        let points = TrackThumbnail.points(
            for: coordinates,
            in: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        )
        guard points.count > 1 else { return nil }
        let list = points
            .map { "\(rounded($0.x)),\(rounded($0.y))" }
            .joined(separator: " ")
        return """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(size.width))" \
            height="\(Int(size.height))" viewBox="0 0 \(Int(size.width)) \
            \(Int(size.height))"><polyline points="\(list)" fill="none" \
            stroke="\(hex)" stroke-width="2" stroke-linecap="round" \
            stroke-linejoin="round"/></svg>
            """
    }

    /// One decimal is plenty at these sizes, and it keeps the file small.
    private static func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
