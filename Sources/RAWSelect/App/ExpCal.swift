import Foundation
import CoreImage
import AppKit

/// Measurement-only calibration probe for EXPOSURE: `RAWSelect --expcal [datei|ordner]`.
///
/// Renders the Adobe reference (Lightroom bridge, neutral base + one exposure value) at fine
/// EV steps and, on the SAME base, the in-app CoreImage approximation. Prints, per step, how
/// much each tonal region (shadows / mids / highlights) and the overall mean actually shift —
/// Adobe vs in-app — plus the ratio. This reveals the RESPONSE CURVE so the mapping can be
/// aligned in proportion across the range instead of fitting one scalar to the extremes.
///
/// It only PRINTS; it never changes DevelopEngine. Lightroom Classic must be running.
enum ExpCal {

    private static let grid = 48
    private static let maxEdge = 900
    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private static let evSteps: [Double] = [-1.0, -0.6, -0.4, -0.2, 0.2, 0.4, 0.6, 1.0, 1.5, 2.0]

    static func run(_ args: [String]) {
        let sem = DispatchSemaphore(value: 0)
        Task { await runAsync(args); sem.signal() }
        sem.wait()
    }

    private static func runAsync(_ args: [String]) async {
        let files = collectRAWs(args)
        guard !files.isEmpty else { print("Keine RAWs. Nutzung: --expcal <datei|ordner>"); return }
        guard LightroomExportService.isAvailable(preferredPath: "") else { print("Lightroom Classic nicht gefunden."); return }
        print("expcal: \(files.count) Bild(er), EV-Schritte \(evSteps)\n")

        for raw in files {
            print("### \(raw.lastPathComponent)")
            guard let baseURL = await render(raw, ImageEdit()), let baseCI = CIImage(contentsOf: baseURL) else {
                print("  Basis-Render fehlgeschlagen\n"); continue
            }
            let base = cells(baseCI)                                  // per-cell luminance of the neutral base
            let (loMask, hiMask) = masks(base)
            print(String(format: "  %-6@ | %-22@ | %-22@ | Verhältnis(gesamt)", "EV" as NSString,
                         "Adobe  S/M/L  gesamt" as NSString, "In-App S/M/L  gesamt" as NSString))
            for ev in evSteps {
                var e = ImageEdit(); e.exposure = ev
                guard let refURL = await render(raw, e), let refCI = CIImage(contentsOf: refURL) else {
                    print(String(format: "  %+.1f  | (Render-Fehler)", ev)); continue
                }
                let ref = cells(refCI)
                let mine = cells(DevelopEngine.apply(e, to: baseCI))
                let a = regionShift(base, ref, loMask, hiMask)
                let m = regionShift(base, mine, loMask, hiMask)
                let ratio = abs(a.all) > 0.5 ? m.all / a.all : Double.nan
                print(String(format: "  %+.1f  | %+5.1f/%+5.1f/%+5.1f %+6.1f | %+5.1f/%+5.1f/%+5.1f %+6.1f | %.2f",
                             ev, a.lo, a.mid, a.hi, a.all, m.lo, m.mid, m.hi, m.all, ratio))
            }
            print("")
        }
        print("Hinweis: Verhältnis In-App/Adobe (gesamt). ~1.0 über alle Schritte = deckt sich; " +
              "steigt/fällt es systematisch, ist die Kurvenform (nicht nur die Stärke) daneben.")
    }

    // MARK: metric

    private static func render(_ raw: URL, _ edit: ImageEdit) async -> URL? {
        await LightroomExportService.renderPreview(rawURL: raw, presetURL: nil, edit: edit,
                                                   maxEdge: maxEdge, lightroomPath: "")?.url
    }

    /// Per-cell luminance (0…255) on a fixed grid, so base/ref/in-app align pixel-for-pixel.
    private static func cells(_ ci: CIImage) -> [Double] {
        let ex = ci.extent
        guard ex.width > 0, ex.height > 0 else { return [] }
        let n = grid
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: CGFloat(n) / ex.width, y: CGFloat(n) / ex.height))
            .transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        var px = [UInt8](repeating: 0, count: n * n * 4)
        ctx.render(scaled, toBitmap: &px, rowBytes: n * 4, bounds: CGRect(x: 0, y: 0, width: n, height: n),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var out = [Double](repeating: 0, count: n * n)
        var j = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            out[j] = 0.299 * Double(px[i]) + 0.587 * Double(px[i+1]) + 0.114 * Double(px[i+2]); j += 1
        }
        return out
    }

    /// Shadow (<85) and highlight (>170) cell masks from the base luminance.
    private static func masks(_ base: [Double]) -> ([Bool], [Bool]) {
        (base.map { $0 < 85 }, base.map { $0 > 170 })
    }

    /// Mean luminance shift (adjusted − base) overall and per tonal region.
    private static func regionShift(_ base: [Double], _ adj: [Double], _ lo: [Bool], _ hi: [Bool])
        -> (lo: Double, mid: Double, hi: Double, all: Double) {
        var sLo = 0.0, nLo = 0, sHi = 0.0, nHi = 0, sMid = 0.0, nMid = 0, sAll = 0.0
        for i in 0..<base.count {
            let d = adj[i] - base[i]; sAll += d
            if lo[i] { sLo += d; nLo += 1 } else if hi[i] { sHi += d; nHi += 1 } else { sMid += d; nMid += 1 }
        }
        func avg(_ s: Double, _ n: Int) -> Double { n > 0 ? s / Double(n) : 0 }
        return (avg(sLo, nLo), avg(sMid, nMid), avg(sHi, nHi), sAll / Double(max(base.count, 1)))
    }

    private static func collectRAWs(_ args: [String]) -> [URL] {
        let exts: Set<String> = ["arw", "cr2", "cr3", "nef", "raf", "rw2", "dng", "orf", "pef"]
        var paths = args.filter { !$0.hasPrefix("-") }
        if paths.isEmpty { paths = [(NSHomeDirectory() as NSString).appendingPathComponent("Downloads")] }
        var out: [URL] = []
        let fm = FileManager.default
        for p in paths {
            let u = URL(fileURLWithPath: p)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                let items = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
                out += items.filter { exts.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else if exts.contains(u.pathExtension.lowercased()) { out.append(u) }
        }
        return Array(out.prefix(2))
    }
}
