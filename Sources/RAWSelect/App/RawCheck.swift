import Foundation

/// Headless RAW diagnosis: `RAWSelect --rawcheck <datei.raw> […]`.
/// Prints, per file, whether macOS can develop the RAW natively, the largest
/// embedded JPEG it could fall back to, and which path the zoom would use — so any
/// new camera/format can be verified in seconds without owning the camera.
enum RawCheck {
    static func run(_ paths: [String]) {
        guard !paths.isEmpty else {
            print("Nutzung: RAWSelect --rawcheck <datei.raw> [weitere Dateien…]")
            return
        }
        print("RAW-Zoom-Diagnose\n")
        for p in paths {
            print(ThumbnailLoader.zoomDecodeReport(url: URL(fileURLWithPath: p)))
        }
    }
}
