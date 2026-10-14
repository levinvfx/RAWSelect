import SwiftUI

/// Central place for the file types and mark styling used across the app.
enum AppInfo {
    static let name = "RAW Select"
    /// Release version. A pre-release carries a suffix ("2.0-beta1"); `UpdateService.isNewer` ranks
    /// it below the final "2.0". Must match `VERSION=` in build_app.sh.
    static let version = "2.0-beta1"
    /// "2.0 Beta 1" — the same version as people read it.
    static var displayVersion: String { version.replacingOccurrences(of: "-beta", with: " Beta ") }
    static var isBeta: Bool { version.contains("-") }


    // Credits / branding
    static let author = "Levin Anneler"
    static let brand = "levin.vfx"
    static let instagramHandle = "levin.vfx"
    static let instagramURL = URL(string: "https://instagram.com/levin.vfx")!
    static let email = "levin@annelers.ch"
    static var emailURL: URL { URL(string: "mailto:\(email)")! }
    /// VFX Media main site (About tab).
    static let companyURL = URL(string: "https://vfxmedia.ch/")!
    /// Official download page (also hosts the privacy statement and imprint).
    static let websiteURL = URL(string: "https://vfxmedia.ch/rawselect/")!
    static let privacyURL = URL(string: "https://vfxmedia.ch/rawselect/#datenschutz")!

    /// Pre-filled feedback mail: version and coarse macOS version go into the body so a bug report
    /// is useful without a back-and-forth. Nothing is sent unless the user hits "Senden".
    static var feedbackURL: URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [
            URLQueryItem(name: "subject", value: "RAW Select \(displayVersion) – Feedback"),
            URLQueryItem(name: "body", value: "\n\n\n—\nRAW Select \(version) · \(TelemetryService.coarseOSVersion)"),
        ]
        return c.url ?? emailURL
    }

    /// Public GitHub repository the auto-updater queries (`releases/latest`, first `.dmg` asset).
    /// Since V1.11 this is a downloads-only repo (DMG + signature, no source) so the source repository
    /// can stay private. Apps ≤ 1.10 still ask the old repo — V1.11 was published to both.
    static let githubRepo = "levinvfx/RAWSelect-Releases"

    /// Ed25519 public key that every update DMG must be signed with (see `UpdateSignature` and
    /// tools/sign_update.swift). The private half never leaves Levin's Mac
    /// (~/.config/rawselect/update-signing.key). Without a valid signature the app refuses an update —
    /// so a hijacked GitHub account or token can no longer push code onto every user's Mac.
    static let updatePublicKey = "8CjOD5QdNg02klSeWcYEOxlyLrKce8hEtDObj/Nm7Sg="

    /// Endpoint of the anonymous usage count (see `TelemetryService`): Levin's own server, which
    /// stores only the random id + version + macOS version, never the IP. `nil` would switch the
    /// feature off entirely; the user-facing switch is Einstellungen → Erweitert.
    static let telemetryEndpoint: URL? = URL(string: "https://vfxmedia.ch/rawselect/ping.php")
}

/// Loads the bundled brand logo (black on light, white on dark). Both variants
/// ship in Contents/Resources; returns nil in a plain `swift run` (no bundle).
enum AppAssets {
    static func logo(dark: Bool) -> NSImage? {
        let name = dark ? "VFXMedia-Weiss" : "VFXMedia-Schwarz"
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

