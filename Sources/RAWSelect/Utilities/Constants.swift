import SwiftUI

/// Central place for the file types and mark styling used across the app.
enum AppInfo {
    static let name = "RAW Select"
    static let version = "1.6"

    /// Der Lightroom-JPEG-Export (via Bridge-Plugin) ist noch in Entwicklung und in
    /// öffentlichen Release-Builds ausgeblendet: das Bridge-Plugin importiert jedes
    /// exportierte RAW als Geist in den Lightroom-Katalog und räumt es nicht weg
    /// (siehe Memory „Katalog-Verschmutzung"). Bis das gelöst ist, darf das Feature
    /// nicht auf fremde Rechner. In Debug-Builds (Levins Entwicklung: `swift build`)
    /// bleibt es sichtbar; `./build_app.sh` baut Release → Feature aus.
    static var lightroomExportEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // Credits / branding
    static let author = "Levin Anneler"
    static let brand = "levin.vfx"
    static let instagramHandle = "levin.vfx"
    static let instagramURL = URL(string: "https://instagram.com/levin.vfx")!
    static let email = "levin@annelers.ch"
    static var emailURL: URL { URL(string: "mailto:\(email)")! }

    /// GitHub repository (owner/name) the auto-updater queries for new releases.
    /// ⚠️ HIER dein echtes ÖFFENTLICHES Repo eintragen, sobald es existiert –
    /// solange das nicht stimmt, findet die App nur „keine Updates“ (404, still).
    static let githubRepo = "levinvfx/RAWSelect"
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
    /// Tiny always-available grid thumbnail (fallback shown instantly while the
    /// sharp version decodes – so scrolling never shows a spinner).
    static let tinyMaxPixel = 160
    /// How many tiny thumbnails to warm right when a folder opens. Bounded so a
    /// huge folder (1000s of RAWs) doesn't flood the decode queue at once — the
    /// rest load lazily on appearance and via the sliding prefetch window.
    static let initialWarmCount = 120
    /// Sharp grid thumbnail size as a factor of the cell side (kept small = fast).
    static let gridSharpFactor: CGFloat = 1.7

    /// Full-res target for the zoom loupe. High enough to be effectively "native"
    /// for any current camera (ImageIO never upscales past the source), so a RAW is
    /// developed at sensor resolution — only while zoomed in, one image at a time.
    static let zoomMaxPixel = 12000
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

