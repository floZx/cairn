import SwiftUI

/// Distinct colours for drawing several tracks on one map.
///
/// A fixed, ordered list rather than generated hues: system colours stay legible
/// over a pale topographic tile and a dark satellite image alike, and follow the
/// appearance on their own. Deliberately unrelated to `TrackColor`, which is the
/// one colour the user picks for a single track — here the point is telling
/// tracks apart, not matching a preference.
///
/// Eight is past the point where more routes stay comparable by eye, so the list
/// repeats rather than drifting into shades nobody can distinguish. A repeat is
/// obvious and harmless; two near-identical greens would be worse.
enum TrackPalette {
    static let colors: [NSColor] = [
        .systemBlue,
        .systemOrange,
        .systemGreen,
        .systemPurple,
        .systemRed,
        .systemTeal,
        .systemBrown,
        .systemPink,
    ]

    /// The colour for a position in the selection, wrapping past the end.
    static func color(at index: Int) -> NSColor {
        // Modulo twice so a negative index still lands in range rather than
        // trapping: nothing passes one today, and a crash would be a poor way
        // to find out that something started to.
        let wrapped = ((index % colors.count) + colors.count) % colors.count
        return colors[wrapped]
    }
}
