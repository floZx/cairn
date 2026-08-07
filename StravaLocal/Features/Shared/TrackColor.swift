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

    /// A filled disc as a non-template bitmap.
    ///
    /// A menu re-tints template images — SF Symbols included — to match its own
    /// styling, so `Image(systemName: "circle.fill").foregroundStyle(color)`
    /// arrives grey in a picker's menu. Drawing the disc ourselves and marking
    /// the image non-template is what keeps the colour.
    @MainActor
    var swatch: NSImage {
        let diameter: CGFloat = 12
        let image = NSImage(
            size: NSSize(width: diameter, height: diameter), flipped: false
        ) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            nsColor.setFill()
            disc.fill()
            // A hairline keeps the black option visible in dark mode.
            NSColor.separatorColor.setStroke()
            disc.lineWidth = 0.5
            disc.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    static let storageKey = "trackColor"
}
