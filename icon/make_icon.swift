import AppKit

// Renders the source logo into a macOS-style rounded icon tile (Apple icon grid:
// ~100px dock padding on a 1024 canvas, corner radius ≈ 22.37% of the tile).
let args = CommandLine.arguments
guard args.count >= 3, let src = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make_icon <src.png> <out1024.png>\n".utf8))
    exit(1)
}
let outPath = args[2]

let px = 1024
let inset: CGFloat = 100
let rectSize = CGFloat(px) - inset * 2      // 824
let radius = rectSize * 0.2237

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

let rect = NSRect(x: inset, y: inset, width: rectSize, height: rectSize)
NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
src.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: outPath))
