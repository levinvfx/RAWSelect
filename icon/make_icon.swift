import AppKit

// Renders the source logo into a macOS-style rounded icon tile (Apple icon grid:
// 100px margin on a 1024 canvas → 824 live area, corner radius ≈ 22.37%).
//
// The source may be a logo tile floating on a white background (with lots of
// margin). We first auto-trim the near-white border so the actual artwork fills
// the icon's live area edge-to-edge and "comes into its own".
let args = CommandLine.arguments
guard args.count >= 3, let src = NSImage(contentsOfFile: args[1]),
      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: make_icon <src.png> <out1024.png>\n".utf8))
    exit(1)
}
let outPath = args[2]

// ---- 1. Read source pixels into RGBA8 ----
let sw = srcCG.width, sh = srcCG.height
var buf = [UInt8](repeating: 0, count: sw * sh * 4)
let cs = CGColorSpaceCreateDeviceRGB()
if let c = CGContext(data: &buf, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4,
                     space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
    c.draw(srcCG, in: CGRect(x: 0, y: 0, width: sw, height: sh))
}

// ---- 2. Bounding box of non-near-white content (top-left origin) ----
// A pixel counts as content if it is meaningfully darker/more saturated than the
// white background. Faint drop shadows (≈250) are intentionally ignored.
func isContent(_ i: Int) -> Bool {
    let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2]), a = Int(buf[i + 3])
    if a < 8 { return false }
    let darkness = 255 - min(r, min(g, b))          // how far from white
    return darkness > 18
}
var minX = sw, minY = sh, maxX = 0, maxY = 0
for y in 0..<sh {
    for x in 0..<sw {
        if isContent((y * sw + x) * 4) {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
if maxX <= minX || maxY <= minY { minX = 0; minY = 0; maxX = sw - 1; maxY = sh - 1 }

// ---- 3. Square the box (centred) with a little breathing room ----
let cx = Double(minX + maxX) / 2, cy = Double(minY + maxY) / 2
let side = Double(max(maxX - minX, maxY - minY))
var half = side / 2 * 1.02                            // 2% padding around the artwork
half = min(half, min(cx, Double(sw) - cx))            // clamp to image bounds
half = min(half, min(cy, Double(sh) - cy))
let cropRect = CGRect(x: cx - half, y: cy - half, width: half * 2, height: half * 2)
let tile = srcCG.cropping(to: cropRect) ?? srcCG
let tileImage = NSImage(cgImage: tile, size: NSSize(width: tile.width, height: tile.height))

// ---- 4. Compose into the macOS icon squircle ----
let px = 1024
let inset: CGFloat = 100
let rectSize = CGFloat(px) - inset * 2               // 824
let radius = rectSize * 0.2237

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

// Background tone sampled from the source corners → seamless margin around the motif.
func cornerColor() -> NSColor {
    let pts = [(2, 2), (sw - 3, 2), (2, sh - 3), (sw - 3, sh - 3)]
    var r = 0, g = 0, b = 0
    for (px, py) in pts { let i = (py * sw + px) * 4; r += Int(buf[i]); g += Int(buf[i + 1]); b += Int(buf[i + 2]) }
    let n = CGFloat(pts.count)
    return NSColor(deviceRed: CGFloat(r) / n / 255, green: CGFloat(g) / n / 255, blue: CGFloat(b) / n / 255, alpha: 1)
}

let rect = NSRect(x: inset, y: inset, width: rectSize, height: rectSize)
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
squircle.addClip()
// Fill the whole squircle face with the logo's background tone (clean, seamless).
cornerColor().setFill()
squircle.fill()
// Draw the motif smaller and CENTRED so it has breathing room and isn't clipped.
let contentScale: CGFloat = 0.80
let cw = rectSize * contentScale
let contentRect = NSRect(x: inset + (rectSize - cw) / 2, y: inset + (rectSize - cw) / 2, width: cw, height: cw)
tileImage.draw(in: contentRect, from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: outPath))
