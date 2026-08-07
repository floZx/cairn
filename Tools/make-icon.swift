#!/usr/bin/env swift
import AppKit

// Generates the app icon into an .appiconset. Kept as a script rather than
// checked-in art alone so the shape can be tweaked and regenerated.
//
// Usage: swift Tools/make-icon.swift <chemin/AppIcon.appiconset>

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Cairn/Assets.xcassets/AppIcon.appiconset"
let output = URL(filePath: outputPath)

/// The four slabs, traced off the reference image and normalised to its ink box.
///
/// Corners are sharp and no two edges are parallel: these are split rocks, not
/// river pebbles. The stack is deliberately off-axis — each slab is nudged left
/// or right of the one below and tilted a degree or two — which is what makes it
/// read as balanced rather than as a stack of bricks. Origin is bottom-left, so
/// the first entry is the slab on the ground.
let slabs: [[(x: CGFloat, y: CGFloat)]] = [
    [(0.002, 0.220), (0.792, 0.185), (0.766, 0.009), (0.006, 0.000)],
    [(0.296, 0.466), (0.969, 0.489), (1.000, 0.265), (0.302, 0.278)],
    [(0.121, 0.759), (0.720, 0.749), (0.712, 0.551), (0.099, 0.554)],
    [(0.457, 1.000), (0.633, 0.992), (0.646, 0.821), (0.457, 0.816)],
]

/// Draws into a bitmap of exactly `size` pixels.
///
/// Not `NSImage.lockFocus`: that renders at the screen's backing scale, so on a
/// Retina Mac every file came out twice its declared size and the asset catalog
/// warned about all ten of them.
func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap impossible à créer") }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("pas de contexte graphique")
    }
    NSGraphicsContext.current = graphicsContext
    graphicsContext.cgContext.setShouldAntialias(true)

    // macOS icons leave a margin: the artwork is a rounded square filling about
    // 80 % of the canvas, not the canvas itself. The reference is a transparent
    // silhouette, but an icon without a plate reads as a broken image in the Dock.
    let inset = size * 0.0977
    let box = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = box.width * 0.225

    let plate = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    plate.addClip()
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.965, green: 0.945, blue: 0.910, alpha: 1),
            NSColor(srgbRed: 0.831, green: 0.796, blue: 0.737, alpha: 1),
        ]
    )?.draw(in: box, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let field = box.insetBy(dx: box.width * 0.13, dy: box.height * 0.13)
    NSColor(srgbRed: 0.075, green: 0.082, blue: 0.090, alpha: 1).setFill()
    for slab in slabs {
        let path = NSBezierPath()
        for (index, corner) in slab.enumerated() {
            let point = CGPoint(
                x: field.minX + field.width * corner.x,
                y: field.minY + field.height * corner.y
            )
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        path.fill()
    }

    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("encodage PNG impossible")
    }
    try png.write(to: url)
}

let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for variant in variants {
    // Drawn at the real pixel count so small sizes stay crisp instead of being a
    // downscale of the 1024 version.
    try write(drawIcon(size: variant.pixels), to: output.appending(path: "\(variant.name).png"))
}
print("icônes écrites dans \(output.path)")
