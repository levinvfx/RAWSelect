import SwiftUI

/// Central place for the file types and mark styling used across the app.
enum AppInfo {
    static let name = "RAW Select"
    static let version = "1.0"

    // Credits / branding
    static let author = "Levin Anneler"
    static let brand = "levin.vfx"
    static let instagramHandle = "levin.vfx"
    static let instagramURL = URL(string: "https://instagram.com/levin.vfx")!
    static let email = "levin@annelers.ch"
    static var emailURL: URL { URL(string: "mailto:\(email)")! }
}

/// Loads the bundled brand logo (black on light, white on dark). Both variants
/// ship in Contents/Resources; returns nil in a plain `swift run` (no bundle).
enum AppAssets {
    static func logo(dark: Bool) -> NSImage? {
        let name = dark ? "Logo-Weiss" : "Logo-Schwarz"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}

/// Sizing for the large loupe preview. Sharp but a touch smaller than the full
/// display resolution, so decoding stays fast and neighbours can be prefetched.
enum PreviewConfig {
    static var loupeMaxPixel: Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let height = NSScreen.main?.frame.height ?? 1080
        return min(2048, max(1600, Int(height * scale)))
    }
    /// How many neighbouring photos to prefetch around the current one.
    static let prefetchForward = 8
    static let prefetchBackward = 4

    /// Tiny always-available grid thumbnail (fallback shown instantly while the
    /// sharp version decodes – so scrolling never shows a spinner).
    static let tinyMaxPixel = 160
    /// Sharp grid thumbnail size as a factor of the cell side (kept small = fast).
    static let gridSharpFactor: CGFloat = 1.7
}

enum PhotoTypes {
    /// All image extensions we scan for (lowercased, without dot).
    static let all: Set<String> = [
        "arw", "cr2", "cr3", "nef", "raf", "dng",
        "jpg", "jpeg", "heic", "png"
    ]

    /// RAW formats – these are never fully developed, we read embedded previews.
    static let raw: Set<String> = ["arw", "cr2", "cr3", "nef", "raf", "dng"]

    /// Formats that are cheap to preview directly. When a photo group contains
    /// one of these next to a RAW file, we prefer it for the on-screen preview.
    static let quickPreview: Set<String> = ["jpg", "jpeg", "heic", "png"]

    static func isRaw(_ url: URL) -> Bool {
        raw.contains(url.pathExtension.lowercased())
    }

    static func isSupported(_ url: URL) -> Bool {
        all.contains(url.pathExtension.lowercased())
    }
}

/// Fixed, distinguishable colors for marks 1–9 (loosely inspired by classic
/// color-class culling, but our own palette). Index 0 is unused (= no mark).
enum MarkStyle {
    static let colors: [Color] = [
        .clear,                                   // 0 – no mark
        Color(red: 0.90, green: 0.24, blue: 0.24), // 1 red
        Color(red: 0.95, green: 0.55, blue: 0.16), // 2 orange
        Color(red: 0.95, green: 0.80, blue: 0.18), // 3 yellow
        Color(red: 0.30, green: 0.72, blue: 0.36), // 4 green
        Color(red: 0.20, green: 0.72, blue: 0.66), // 5 teal
        Color(red: 0.22, green: 0.52, blue: 0.92), // 6 blue
        Color(red: 0.45, green: 0.40, blue: 0.90), // 7 indigo
        Color(red: 0.83, green: 0.35, blue: 0.72), // 8 pink
        Color(red: 0.55, green: 0.47, blue: 0.42)  // 9 taupe
    ]

    static func color(for mark: Int) -> Color {
        guard mark >= 1 && mark <= 9 else { return .clear }
        return colors[mark]
    }

    /// Subfolder name used when copying/moving, e.g. mark 1 -> "01_Mark_1".
    static func folderName(for mark: Int) -> String {
        String(format: "%02d_Mark_%d", mark, mark)
    }
}
