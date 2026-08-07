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

// A pebble: points sampled around an ellipse, each nudged by a fixed offset, then
// joined through their midpoints so every corner comes out rounded. Fixed
// offsets rather than random ones keep two runs of the script identical.
func pebble(center: CGPoint, width: CGFloat, height: CGFloat, wobble: [CGFloat]) -> NSBezierPath {
    let count = wobble.count
    let points = (0..<count).map { i -> CGPoint in
        let angle = 2 * .pi * CGFloat(i) / CGFloat(count)
        // Joining through midpoints pulls the outline inside the sampled points,
        // so the samples are pushed out to land back on the requested size.
        let scale = 1.12 * (1 + wobble[i])
        return CGPoint(
            x: center.x + cos(angle) * width / 2 * scale,
            y: center.y + sin(angle) * height / 2 * scale
        )
    }
    func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    let path = NSBezierPath()
    path.move(to: midpoint(points[count - 1], points[0]))
    for i in 0..<count {
        let next = points[(i + 1) % count]
        path.curve(to: midpoint(points[i], next), controlPoint: points[i])
    }
    path.close()
    return path
}

/// Stones bottom-up: centre and size in the content box, plus the wobble that
/// makes each one a different stone instead of the same ellipse four times.
let stones: [(y: CGFloat, w: CGFloat, h: CGFloat, dx: CGFloat, wobble: [CGFloat])] = [
    (0.115, 0.86, 0.22, 0.000, [0.03, -0.05, 0.04, 0.02, -0.04, 0.05, -0.03, 0.02]),
    (0.335, 0.66, 0.20, 0.020, [-0.04, 0.05, -0.02, 0.04, 0.03, -0.05, 0.02, -0.03]),
    (0.545, 0.48, 0.18, -0.030, [0.05, 0.02, -0.04, 0.03, -0.03, 0.04, 0.02, -0.05]),
    (0.730, 0.33, 0.16, 0.015, [-0.03, 0.04, 0.02, -0.05, 0.04, -0.02, 0.05, -0.04]),
    (0.885, 0.18, 0.12, -0.010, [0.04, -0.03, 0.05, 0.02, -0.04, 0.03, -0.05, 0.02]),
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
    let context = graphicsContext.cgContext
    context.setShouldAntialias(true)

    // macOS icons leave a margin: the artwork is a rounded square filling about
    // 80 % of the canvas, not the canvas itself.
    let inset = size * 0.0977
    let box = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = box.width * 0.225

    let plate = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    context.saveGState()
    plate.addClip()
    let gradient = NSGradient(
        colors: [
            NSColor(srgbRed: 0.965, green: 0.945, blue: 0.910, alpha: 1),
            NSColor(srgbRed: 0.831, green: 0.796, blue: 0.737, alpha: 1),
        ]
    )
    gradient?.draw(in: box, angle: -90)
    context.restoreGState()

    // The stones sit in the lower-middle of the plate, leaving air above the top
    // pebble so the stack reads as a cairn rather than a filled column.
    let field = box.insetBy(dx: box.width * 0.11, dy: box.height * 0.08)
    NSColor(srgbRed: 0.129, green: 0.145, blue: 0.157, alpha: 1).setFill()
    for stone in stones {
        pebble(
            center: CGPoint(
                x: field.midX + field.width * stone.dx,
                y: field.minY + field.height * stone.y
            ),
            width: field.width * stone.w,
            height: field.height * stone.h,
            wobble: stone.wobble
        ).fill()
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
