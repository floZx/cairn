import SwiftUI

/// The open activity's colour, laid over a frosted surface.
///
/// A window material blends the desktop and nothing of the app, so the sport's
/// light cannot reach these panes by translucency alone: it is painted over
/// the material and under the content.
///
/// Stops rather than a fixed height. A gradient handed its own frame inside a
/// background lands where the layout decides, not where it was meant to — that
/// came out once as a hard-edged red band across the sidebar's sport filters.
/// Fading by proportion of the surface cannot produce an edge at all.
struct SportWash: ViewModifier {
    /// Nothing open, nothing to borrow a colour from.
    let color: Color?

    /// A fraction of `AmbientGlow`'s own opacity, so the three stay tied: the
    /// header lights its block with the glow, and these washes lie under it.
    let strength: Double

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            if let color {
                LinearGradient(
                    stops: [
                        .init(
                            color: color.opacity(
                                AmbientGlow.opacity(for: colorScheme) * strength
                            ),
                            location: 0
                        ),
                        .init(color: .clear, location: 0.45),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Applied *before* the material behind it: each `background` sits behind
    /// the view it modifies, so the material must come second to end up under
    /// the wash rather than over it.
    func sportWash(_ color: Color?, strength: Double) -> some View {
        modifier(SportWash(color: color, strength: strength))
    }
}

/// How much of the glow each surface takes.
enum SportWashStrength {
    /// The pane the activity is actually about.
    static let detail = 0.35
    /// The navigation beside it, which only shares in the light.
    static let sidebar = 0.6
}
