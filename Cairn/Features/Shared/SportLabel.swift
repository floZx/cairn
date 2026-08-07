import SwiftUI

extension SportType {
    /// A colour per sport, so a list of activities can be read by shape *and* by
    /// hue at a glance.
    ///
    /// Grouped rather than scattered: the four bikes share the blue end, the two
    /// running sports the warm end, and the two on foot the earthy one. Related
    /// sports reading as related is worth more than fourteen maximally distant
    /// hues, which would only be fourteen colours nobody can attach a meaning to.
    ///
    /// System colours throughout, so every one of them adapts to light and dark
    /// on its own — a hand-picked hex that reads well on white routinely
    /// disappears on charcoal.
    var color: Color {
        switch self {
        case .ride: .blue
        case .eBikeRide: .cyan
        case .mountainBikeRide: .indigo
        case .gravelRide: .teal
        case .run: .orange
        case .trailRun: .red
        case .walk: .brown
        case .hike: .green
        case .swim: .mint
        case .nordicSki: .purple
        case .alpineSki: .pink
        case .rowing: .yellow
        case .workout: .gray
        // Nothing to say about a sport we did not recognise, so it says nothing.
        case .other: .secondary
        }
    }
}

/// A label whose icon carries the sport's colour while the text stays plain.
///
/// `Label(_:systemImage:)` tints icon and text together, which in a list of
/// activity names would turn every row into coloured text — unreadable, and
/// wrong: the colour identifies the sport, not the name.
///
/// The icon also sits in a gutter of its own width, so every title in a list
/// starts at the same place. SF Symbols are not monospaced: measured at a 13 pt
/// body font, `bicycle` is 24 pt wide against 12 for `figure.walk`, and that
/// twelve-point swing moved the text of every row.
///
/// One caveat, and it is AppKit's: a menu re-tints template images to match its
/// own styling, so the icon inside a `Picker`'s pop-up arrives in the menu's
/// colour rather than the sport's. `TrackColor.swatch` works around that by
/// drawing a bitmap; it is not worth the same trouble here, where the sport's
/// name is right beside the icon.
struct SportLabel: View {
    let title: String
    let sport: SportType

    init(_ title: String, sport: SportType) {
        self.title = title
        self.sport = sport
    }

    var body: some View {
        GutteredLabel(title, systemImage: sport.symbolName, tint: sport.color)
    }
}

/// A label whose symbol sits in a gutter of fixed width.
///
/// SF Symbols are not monospaced. Measured at a 13 pt body font: `bicycle` is
/// 24 pt wide against 12 for `figure.walk`, and `house` 19 against 13 for
/// `lock`. `Label` places the title right after whatever width the symbol
/// happens to have, so in a list every row started somewhere slightly different.
///
/// One gutter for the whole app rather than one per family: the sidebar puts a
/// list of sports directly above a list of markers, and two different alignments
/// there would be more visible than the ragged edge this fixes.
struct GutteredLabel: View {
    let title: String
    let systemImage: String
    /// Nil leaves the symbol to inherit the label's own colour, which is what a
    /// plain marker wants; a sport passes its own.
    var tint: Color?

    /// Sized for the widest symbol in use, `bicycle`. Scaled rather than fixed
    /// so the gutter keeps up when the text grows.
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 24

    init(_ title: String, systemImage: String, tint: Color? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    /// The gutter as laid out, so a test can check no symbol overflows it.
    /// `@ScaledMetric` is only resolved inside a view hierarchy, hence reading
    /// it through the view rather than asserting on the constant.
    var gutterWidthForTesting: CGFloat { width }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? .primary)
                // Centred in the gutter: padding a narrow symbol on one side
                // only would trade misaligned text for misaligned icons.
                .frame(width: width, alignment: .center)
        }
    }
}
