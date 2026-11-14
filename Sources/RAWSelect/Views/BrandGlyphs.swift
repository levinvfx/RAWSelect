import AppKit

/// Icons of the toolbar tiles: the real logos of the destinations and a line glyph for Copy.
/// Glyphs are drawn on an 18-unit canvas with y pointing down.
enum BrandGlyph {
    private static let lineWidth: CGFloat = 1.5

    private static func glyph(_ draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func stroke(_ path: NSBezierPath) {
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    /// Two sheets, the back one hidden behind the front one.
    static let copy = glyph {
        stroke(NSBezierPath(roundedRect: NSRect(x: 6, y: 5.5, width: 10, height: 11), xRadius: 2.2, yRadius: 2.2))
        let back = NSBezierPath()
        back.move(to: CGPoint(x: 3.6, y: 12.4))
        back.curve(to: CGPoint(x: 2, y: 10.6), controlPoint1: CGPoint(x: 2.6, y: 12.2), controlPoint2: CGPoint(x: 2, y: 11.5))
        back.line(to: CGPoint(x: 2, y: 3.7))
        back.curve(to: CGPoint(x: 4.2, y: 1.5), controlPoint1: CGPoint(x: 2, y: 2.4), controlPoint2: CGPoint(x: 2.9, y: 1.5))
        back.line(to: CGPoint(x: 10, y: 1.5))
        back.curve(to: CGPoint(x: 12, y: 3.2), controlPoint1: CGPoint(x: 11.1, y: 1.5), controlPoint2: CGPoint(x: 11.8, y: 2.2))
        stroke(back)
    }

    /// The Google Drive triangle in its colours. Drawn rather than taken from the app, so it is
    /// there on every Mac, with or without Google Drive installed. Not a template.
    static let googleDrive: NSImage = {
        let topLeft = CGPoint(x: 6.2, y: 2.5), topRight = CGPoint(x: 11.8, y: 2.5)
        let right = CGPoint(x: 17, y: 11.5), bottomRight = CGPoint(x: 14.2, y: 16)
        let bottomLeft = CGPoint(x: 3.8, y: 16), left = CGPoint(x: 1, y: 11.5)
        let innerTop = CGPoint(x: 9, y: 7.34)
        let innerLeft = CGPoint(x: 6.6, y: 11.5), innerRight = CGPoint(x: 11.4, y: 11.5)
        let bars: [(NSColor, [CGPoint])] = [
            (NSColor(srgbRed: 0.06, green: 0.62, blue: 0.35, alpha: 1), [topLeft, innerTop, bottomLeft, left]),
            (NSColor(srgbRed: 0.26, green: 0.52, blue: 0.96, alpha: 1), [innerLeft, right, bottomRight, bottomLeft]),
            (NSColor(srgbRed: 0.96, green: 0.71, blue: 0.0, alpha: 1), [topLeft, topRight, right, innerRight]),
        ]
        return NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            for (color, points) in bars {
                let path = NSBezierPath()
                path.move(to: points[0])
                for point in points.dropFirst() { path.line(to: point) }
                path.close()
                color.set()
                path.fill()
            }
            return true
        }
    }()

    static let finderPath = "/System/Library/CoreServices/Finder.app"

    @MainActor private static var iconCache: [String: NSImage] = [:]

    /// The real icon of an installed app at toolbar size, nil if it isn't there. Cached: the
    /// toolbar redraws on every selection change.
    @MainActor static func appIcon(path: String) -> NSImage? {
        if let hit = iconCache[path] { return hit }
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path),
              let icon = NSWorkspace.shared.icon(forFile: path).copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 23, height: 23)
        iconCache[path] = icon
        return icon
    }
}
