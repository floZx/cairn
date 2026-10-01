import Testing
import AppKit
@testable import Cairn

@Suite("Tuiles topographiques de nuit")
struct RasterDarkTests {
    /// Une tuile blanche — le papier de la carte — devient sombre.
    @Test func whiteTileTurnsDark() throws {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
        let png = try #require(
            image.tiffRepresentation
                .flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:])
        )
        let dark = try #require(RasterTileOverlay.darkened(png, level: 0.5))
        #expect(RasterTileOverlay.looksLikeAnImage(dark))
        let rep = try #require(NSBitmapImageRep(data: dark))
        let pixel = try #require(rep.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
        #expect(pixel.brightnessComponent < 0.3)
    }
}
