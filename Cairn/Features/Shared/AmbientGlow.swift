import SwiftUI

/// A soft wash of colour behind a view, spilling a little past its edges.
///
/// The effect Apple Music uses around artwork: the neighbouring surface is not
/// coloured, it is *lit*. Two things make it read as light rather than as a
/// tinted box — the blur is wide relative to the shape, and the opacity is low
/// enough that the wash is felt before it is seen. Either one alone gives a
/// coloured rectangle.
///
/// Drawn in `background`, which does not clip: the blur is what carries the
/// colour onto whatever sits alongside, and clipping it would remove the point.
struct AmbientGlow: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    let blurRadius: CGFloat

    @Environment(\.colorScheme) private var scheme

    /// A wash reads very differently on the two backgrounds.
    ///
    /// The same alpha that is barely visible over white turns muddy over
    /// near-black, where a colour has nothing to lighten and only greys the
    /// surface. Dark mode gets more of it, and the numbers are separated so the
    /// difference is a decision rather than an accident.
    /// Dialled down twice against Apple Music, which is the reference here and
    /// is far fainter than it looks from memory: the colour registers as a
    /// change of mood, and you cannot point at where it starts. Both schemes
    /// moved together each time — what holds the effect up is the ratio between
    /// them, not the absolute values.
    static func opacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.075 : 0.04
    }

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.opacity(Self.opacity(for: scheme)))
                // Grown before it is blurred: a wash exactly the size of the
                // content fades out at its own edge, so the middle glows and
                // the border does not. Spreading it first puts the falloff
                // outside the content instead.
                .padding(-blurRadius / 2)
                .blur(radius: blurRadius)
        }
    }
}

extension View {
    /// - Parameter blurRadius: wide relative to the view, or the wash reads as
    ///   a coloured box rather than as light.
    func ambientGlow(
        _ color: Color, cornerRadius: CGFloat = 12, blurRadius: CGFloat = 55
    ) -> some View {
        modifier(
            AmbientGlow(
                color: color, cornerRadius: cornerRadius, blurRadius: blurRadius
            )
        )
    }
}
