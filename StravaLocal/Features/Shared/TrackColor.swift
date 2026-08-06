import SwiftUI

/// The colour tracks are drawn in, on every map.
///
/// A closed list of system colours rather than a free picker: the same choice
/// has to stay legible over a pale topographic tile, a dark satellite image and
/// Apple's plan, and an arbitrary hex value can fail all three.
enum TrackColor: String, CaseIterable, Identifiable, Sendable {
    case accent
    case blue
    case orange
    case red
    case magenta
    case purple
    case black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accent: "Couleur d'accentuation"
        case .blue: "Bleu"
        case .orange: "Orange"
        case .red: "Rouge"
        case .magenta: "Magenta"
        case .purple: "Violet"
        case .black: "Noir"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .accent: .controlAccentColor
        case .blue: .systemBlue
        case .orange: .systemOrange
        case .red: .systemRed
        case .magenta: .magenta
        case .purple: .systemPurple
        case .black: .black
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    static let storageKey = "trackColor"
}
