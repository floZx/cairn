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
        Label {
            Text(title)
        } icon: {
            Image(systemName: sport.symbolName)
                .foregroundStyle(sport.color)
        }
    }
}
