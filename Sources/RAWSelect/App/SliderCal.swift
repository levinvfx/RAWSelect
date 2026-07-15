import Foundation
import CoreImage
import AppKit

/// Measurement-only calibration probe: `RAWSelect --slidercal <regler> [raw] [--preset <xmp>]`.
///
/// For one slider it renders, at several values across the working range, the Adobe reference
/// (Lightroom bridge, on the REAL preset — the way the app is actually used) and the in-app
/// CoreImage approximation on the same base. It writes a side-by-side contact sheet per slider
/// and prints the effect strength per tonal region / colour channel, so the response CURVE can
/// be compared instead of one scalar at the extremes.
///
/// It only MEASURES and PRINTS; it never changes `DevelopEngine`. Lightroom Classic must run.
///
/// Two traps this deliberately avoids, both of which wrecked earlier attempts:
///  - The context below must match the app's (default working colour space = linear light).
///    Measuring through `.workingColorSpace: NSNull()` runs the filters on gamma-encoded
///    values, which overstated every effect ~2.5× and drove the fitted values far too weak.
///  - Fitting a scalar to minimise average pixel error at extreme slider values collapses the
///    magnitude when the filter SHAPE differs from Adobe's. Judge the curve, not the mean.
enum SliderCal {

    /// Exactly the context `CropEditorView` renders its live preview with.
    private static let ctx = CIContext(options: [.useSoftwareRenderer: false])
    private static let grid = 64
    private static let maxEdge = 700

    private struct Knob {
        let name: String
        let key: String                   // crs key — its value in the preset is the slider's base
        let steps: [Double]               // desired deltas; trimmed to whatever the base allows
        let colour: Bool                  // true → report RGB channels instead of tonal regions
        /// Hue (degrees) this knob targets. The metric then only looks at pixels actually in
        /// that band — a whole-image mean drowns a band out (the Red band on a football pitch
        /// is a rounding error, and every reading came back ~0.0, looking like a dead slider).
        var bandHue: Double? = nil
        let make: (Double) -> ImageEdit
    }

    private static func knobs() -> [Knob] {
        func tone(_ n: String, _ k: String, _ vals: [Double],
                  _ set: @escaping (inout ImageEdit, Double) -> Void) -> Knob {
            Knob(name: n, key: k, steps: vals, colour: false) { v in var e = ImageEdit(); set(&e, v); return e }
        }
        func colour(_ n: String, _ k: String, _ vals: [Double], band: Double? = nil,
                    _ set: @escaping (inout ImageEdit, Double) -> Void) -> Knob {
            Knob(name: n, key: k, steps: vals, colour: true, bandHue: band) { v in
                var e = ImageEdit(); set(&e, v); return e
            }
        }
        let toneVals: [Double] = [-80, -40, -20, 20, 40, 80]
        return [
            tone("exposure",   "Exposure2012",   [-1.0, -0.6, -0.3, 0.3, 0.6, 1.0]) { $0.exposure = $1 },
            tone("contrast",   "Contrast2012",   toneVals) { $0.contrast = $1 },
            tone("highlights", "Highlights2012", toneVals) { $0.highlights = $1 },
            tone("shadows",    "Shadows2012",    toneVals) { $0.shadows = $1 },
            tone("whites",     "Whites2012",     toneVals) { $0.whites = $1 },
            tone("blacks",     "Blacks2012",     toneVals) { $0.blacks = $1 },
            colour("temp", "Temperature", [-1200, -600, -300, 300, 600, 1200]) { $0.temp = $1 },
            colour("tint", "Tint", [-40, -20, -10, 10, 20, 40]) { $0.tint = $1 },
            // Probed on the Blue band: the sky is a large, clean, unambiguous area of this
            // frame, so the band actually carries signal.
            colour("hslsat", "SaturationAdjustmentBlue", toneVals, band: 240) { $0.hsl["SaturationAdjustmentBlue"] = $1 },
            colour("hslhue", "HueAdjustmentBlue", toneVals, band: 240) { $0.hsl["HueAdjustmentBlue"] = $1 },
            colour("hsllum", "LuminanceAdjustmentBlue", toneVals, band: 240) { $0.hsl["LuminanceAdjustmentBlue"] = $1 },
        ]
    }

    /// Camera Raw's accepted range per control (mirrors `XMPPresetBuilder`).
    private static func acrRange(_ key: String) -> ClosedRange<Double> {
        switch key {
        case "Temperature":  return 2000...50000
        case "Tint":         return -150...150
        case "Exposure2012": return -5...5
        default:             return -100...100
        }
    }

    /// Trims the desired deltas to what this preset's base actually allows. Real presets are
    /// never neutral — this one sits at Highlights -87 — so a symmetric ±80 sweep would push
    /// the absolute value out of range, where Camera Raw discards it and resets the control
    /// to 0. That produced "identical, and brighter" readings that looked like a slider bug.
    private static func usableSteps(_ knob: Knob, base: Double) -> [Double] {
        let r = acrRange(knob.key)
        let lo = r.lowerBound - base, hi = r.upperBound - base
        var out: [Double] = []
        for s in knob.steps {
            let d = s < 0 ? Swift.max(s, lo) : Swift.min(s, hi)
            if abs(d) > 0.001, !out.contains(where: { abs($0 - d) < 0.001 }) { out.append(d) }
        }
        return out.sorted()
    }

    static func run(_ args: [String]) {
        let sem = DispatchSemaphore(value: 0)
        Task { await runAsync(args); sem.signal() }
        sem.wait()
    }

    private static func runAsync(_ args: [String]) async {
        var rest = args
        var presetURL: URL?
        if let i = rest.firstIndex(of: "--preset"), i + 1 < rest.count {
            presetURL = URL(fileURLWithPath: rest[i + 1])
            rest.removeSubrange(i...(i + 1))
        }
        let wanted = rest.filter { !$0.hasPrefix("-") && !$0.contains("/") && !$0.lowercased().hasSuffix(".arw") }
        let all = knobs()
        let picked = wanted.isEmpty ? all : all.filter { wanted.contains($0.name) }
        guard !picked.isEmpty else {
            print("Unbekannter Regler. Verfügbar: \(all.map(\.name).joined(separator: ", "))"); return
        }
        guard let raw = firstRAW(rest) else { print("Kein RAW gefunden."); return }
        guard LightroomExportService.isAvailable(preferredPath: "") else {
            print("Lightroom Classic nicht gefunden / läuft nicht."); return
        }

        let outDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("slidercal", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        print("slidercal: \(raw.lastPathComponent) · Preset \(presetURL?.lastPathComponent ?? "(keins)")")

        guard let baseURL = await render(raw, presetURL, ImageEdit()), let baseCI = CIImage(contentsOf: baseURL) else {
            print("Basis-Render fehlgeschlagen — läuft Lightroom, ist das Plugin geladen?"); return
        }
        if let wb = await LightroomPreviewService.shared.asShotWB(rawURL: raw) {
            print(String(format: "As-Shot WB: %.0f K / Tint %.0f", wb.temp, wb.tint))
        }
        let baseCells = cells(baseCI)
        let (loMask, hiMask) = masks(baseCells)
        guard let baseCG = ctx.createCGImage(baseCI, from: baseCI.extent) else { print("Basis-Bitmap fehlgeschlagen"); return }

        let presetVals = XMPPresetBuilder.presetValues(presetURL)
        let asShot = await LightroomPreviewService.shared.asShotWB(rawURL: raw)

        for knob in picked {
            // The slider's base: the preset's own value, or — for WB, which presets usually
            // leave "As Shot" — the RAW's as-shot value. Deltas are measured from there.
            let base = presetVals[knob.key]
                ?? (knob.key == "Temperature" ? asShot?.temp : knob.key == "Tint" ? asShot?.tint : nil)
                ?? 0
            let steps = usableSteps(knob, base: base)
            print("\n### \(knob.name)   (Cal: \(calDescription(knob.name)))")
            print(String(format: "  Preset-Basis %@ = %.0f → Delta-Fenster %.0f…%.0f",
                         knob.key, base, acrRange(knob.key).lowerBound - base,
                         acrRange(knob.key).upperBound - base))
            if steps.count < knob.steps.count {
                print("  (Schritte ans Fenster angepasst: \(steps.map { fmt($0) }.joined(separator: ", ")))")
            }
            print(knob.colour ? "  Delta   → abs | Adobe  R/G/B          | In-App R/G/B          | Verhältnis"
                              : "  Delta   → abs | Adobe  S/M/L  gesamt  | In-App S/M/L  gesamt  | Verhältnis")
            var tiles: [(String, CGImage, CGImage)] = [("0 (Basis)", baseCG, baseCG)]
            for v in steps {
                let e = knob.make(v)
                let absLabel = String(format: "%+7.1f → %-5.0f", v, base + v)
                guard let refURL = await render(raw, presetURL, e), let refCI = CIImage(contentsOf: refURL) else {
                    print("  \(absLabel) | (Render-Fehler)"); continue
                }
                let mineCI = DevelopEngine.apply(e, to: baseCI)
                if knob.colour {
                    let a = channelShift(baseCI, refCI, bandHue: knob.bandHue)
                    let m = channelShift(baseCI, mineCI, bandHue: knob.bandHue)
                    let ratio = magnitude(a) > 0.5 ? magnitude(m) / magnitude(a) : Double.nan
                    print(String(format: "  %@ | %+5.1f/%+5.1f/%+5.1f       | %+5.1f/%+5.1f/%+5.1f       | %.2f",
                                 absLabel, a.0, a.1, a.2, m.0, m.1, m.2, ratio))
                } else {
                    let a = regionShift(baseCells, cells(refCI), loMask, hiMask)
                    let m = regionShift(baseCells, cells(mineCI), loMask, hiMask)
                    let ratio = abs(a.all) > 0.5 ? m.all / a.all : Double.nan
                    print(String(format: "  %@ | %+5.1f/%+5.1f/%+5.1f %+6.1f | %+5.1f/%+5.1f/%+5.1f %+6.1f | %.2f",
                                 absLabel, a.lo, a.mid, a.hi, a.all, m.lo, m.mid, m.hi, m.all, ratio))
                }
                if let rCG = ctx.createCGImage(refCI, from: refCI.extent),
                   let mCG = ctx.createCGImage(mineCI, from: mineCI.extent) {
                    tiles.append((String(format: "%@ (abs %.0f)", fmt(v), base + v), rCG, mCG))
                }
            }
            let sheetURL = outDir.appendingPathComponent("\(knob.name).png")
            if writeSheet(tiles, title: knob.name, to: sheetURL) { print("  Kontaktbogen: \(sheetURL.path)") }
        }
        print("\nVerhältnis = In-App / Adobe. ~1.0 über ALLE Schritte = deckt sich. Konstant daneben → Stärke;")
        print("systematisch driftend → Kurvenform. Immer auch den Kontaktbogen anschauen, nicht nur die Zahl.")
    }

    private static func fmt(_ v: Double) -> String {
        abs(v) < 10 ? String(format: "%+.1f", v) : String(format: "%+.0f", v)
    }

    /// The Cal constant currently in effect, so the printout is self-documenting.
    private static func calDescription(_ name: String) -> String {
        switch name {
        case "exposure":   return "exposure \(DevelopEngine.Cal.exposure)"
        case "contrast":   return "contrast \(DevelopEngine.Cal.contrast), cap \(DevelopEngine.Cal.contrastCap)"
        case "highlights": return "highlights \(DevelopEngine.Cal.highlights)"
        case "shadows":    return "shadows \(DevelopEngine.Cal.shadows)"
        case "whites":     return "whites +\(DevelopEngine.Cal.whitesPos)^\(DevelopEngine.Cal.whitesPosExp) / -\(DevelopEngine.Cal.whitesNeg)^\(DevelopEngine.Cal.whitesNegExp)"
        case "blacks":     return "blacks +\(DevelopEngine.Cal.blacksPos)^\(DevelopEngine.Cal.blacksPosExp) / -\(DevelopEngine.Cal.blacksNeg)^\(DevelopEngine.Cal.blacksNegExp)"
        case "temp":       return "temp \(DevelopEngine.Cal.temp)"
        case "tint":       return "tint \(DevelopEngine.Cal.tint)"
        case "hslsat":     return "hslSat +\(DevelopEngine.Cal.hslSatPos) / -\(DevelopEngine.Cal.hslSatNeg)"
        case "hslhue":     return "hslHueDeg \(DevelopEngine.Cal.hslHueDeg)"
        case "hsllum":     return "hslLum \(DevelopEngine.Cal.hslLum)"
        default:           return "—"
        }
    }

    // MARK: render

    /// Goes through `LightroomPreviewService` — exactly the path the app renders with. That
    /// matters beyond fidelity: it is the only path that records the RAW's as-shot white
    /// balance, which the WB sliders need as their base. Calling `renderPreview` directly left
    /// the base at 0, so no WB was written at all and Adobe rendered no change.
    /// It also caches, so re-runs after a Cal tweak only re-render what actually changed.
    private static func render(_ raw: URL, _ preset: URL?, _ edit: ImageEdit) async -> URL? {
        await LightroomPreviewService.shared.preview(rawURL: raw, presetURL: preset, edit: edit,
                                                     maxEdge: maxEdge, lightroomPath: "")
    }

    // MARK: metrics

    /// Per-cell luminance (0…255) on a fixed grid, so base/ref/in-app align cell-for-cell.
    private static func cells(_ ci: CIImage) -> [Double] {
        let ex = ci.extent
        guard ex.width > 0, ex.height > 0 else { return [] }
        let n = grid
        let scaled = ci.transformed(by: CGAffineTransform(translationX: -ex.minX, y: -ex.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(n) / ex.width, y: CGFloat(n) / ex.height))
        var px = [UInt8](repeating: 0, count: n * n * 4)
        ctx.render(scaled, toBitmap: &px, rowBytes: n * 4, bounds: CGRect(x: 0, y: 0, width: n, height: n),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var out = [Double](repeating: 0, count: n * n)
        var j = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            out[j] = 0.299 * Double(px[i]) + 0.587 * Double(px[i+1]) + 0.114 * Double(px[i+2]); j += 1
        }
        return out
    }

    /// Mean per-channel RGB (0…255) on the same grid — for the colour controls.
    private static func rgbCells(_ ci: CIImage) -> [(Double, Double, Double)] {
        let ex = ci.extent
        guard ex.width > 0, ex.height > 0 else { return [] }
        let n = grid
        let scaled = ci.transformed(by: CGAffineTransform(translationX: -ex.minX, y: -ex.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(n) / ex.width, y: CGFloat(n) / ex.height))
        var px = [UInt8](repeating: 0, count: n * n * 4)
        ctx.render(scaled, toBitmap: &px, rowBytes: n * 4, bounds: CGRect(x: 0, y: 0, width: n, height: n),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var out: [(Double, Double, Double)] = []
        out.reserveCapacity(n * n)
        for i in stride(from: 0, to: px.count, by: 4) {
            out.append((Double(px[i]), Double(px[i+1]), Double(px[i+2])))
        }
        return out
    }

    /// Mean RGB shift (adjusted − base) per channel. With `bandHue` set, only pixels whose
    /// BASE colour actually sits in that hue band are averaged — otherwise a band covering a
    /// small part of the frame vanishes into the whole-image mean.
    private static func channelShift(_ base: CIImage, _ adj: CIImage,
                                     bandHue: Double? = nil) -> (Double, Double, Double) {
        let b = rgbCells(base), a = rgbCells(adj)
        guard b.count == a.count, !b.isEmpty else { return (0, 0, 0) }
        var r = 0.0, g = 0.0, bl = 0.0, n = 0.0
        for i in 0..<b.count {
            if let h = bandHue, !inBand(b[i], h) { continue }
            r += a[i].0 - b[i].0; g += a[i].1 - b[i].1; bl += a[i].2 - b[i].2; n += 1
        }
        guard n > 0 else { return (0, 0, 0) }
        return (r / n, g / n, bl / n)
    }

    /// True when a pixel is coloured enough and close enough in hue to count for a band.
    private static func inBand(_ px: (Double, Double, Double), _ centre: Double) -> Bool {
        let r = px.0 / 255, g = px.1 / 255, b = px.2 / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0.10 else { return false }          // near-neutral pixels carry no hue
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        var dist = abs(h - centre)
        if dist > 180 { dist = 360 - dist }
        return dist <= 40
    }

    /// Overall size of a colour shift — how far the channels moved, in any direction.
    private static func magnitude(_ s: (Double, Double, Double)) -> Double {
        (abs(s.0) + abs(s.1) + abs(s.2)) / 3
    }

    /// Shadow (<85) and highlight (>170) cell masks from the base luminance.
    private static func masks(_ base: [Double]) -> ([Bool], [Bool]) {
        (base.map { $0 < 85 }, base.map { $0 > 170 })
    }

    /// Mean luminance shift (adjusted − base) overall and per tonal region.
    private static func regionShift(_ base: [Double], _ adj: [Double], _ lo: [Bool], _ hi: [Bool])
        -> (lo: Double, mid: Double, hi: Double, all: Double) {
        guard base.count == adj.count, !base.isEmpty else { return (0, 0, 0, 0) }
        var sLo = 0.0, nLo = 0, sHi = 0.0, nHi = 0, sMid = 0.0, nMid = 0, sAll = 0.0
        for i in 0..<base.count {
            let d = adj[i] - base[i]; sAll += d
            if lo[i] { sLo += d; nLo += 1 } else if hi[i] { sHi += d; nHi += 1 } else { sMid += d; nMid += 1 }
        }
        func avg(_ s: Double, _ n: Int) -> Double { n > 0 ? s / Double(n) : 0 }
        return (avg(sLo, nLo), avg(sMid, nMid), avg(sHi, nHi), sAll / Double(base.count))
    }

    // MARK: contact sheet

    /// Writes rows of [Adobe | In-App] so the pairs can actually be LOOKED at — the numbers
    /// alone hide shape errors (right average, wrong tonal zone).
    private static func writeSheet(_ tiles: [(String, CGImage, CGImage)], title: String, to url: URL) -> Bool {
        guard let first = tiles.first else { return false }
        let tw = CGFloat(first.1.width), th = CGFloat(first.1.height)
        let gap: CGFloat = 8, label: CGFloat = 22, head: CGFloat = 26
        let w = tw * 2 + gap * 3
        let h = head + (th + label + gap) * CGFloat(tiles.count) + gap

        guard let cg = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        cg.setFillColor(CGColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let ns = NSGraphicsContext(cgContext: cg, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 12, bold: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.white,
            ]
            NSAttributedString(string: s, attributes: attrs).draw(at: NSPoint(x: x, y: y))
        }
        text("\(title)  —  links: Adobe (Lightroom)   ·   rechts: In-App (Live-Vorschau)",
             gap, h - head + 6, size: 13, bold: true)

        var y = h - head - gap
        for (lab, adobe, mine) in tiles {
            y -= th
            cg.draw(adobe, in: CGRect(x: gap, y: y, width: tw, height: th))
            cg.draw(mine, in: CGRect(x: gap * 2 + tw, y: y, width: CGFloat(mine.width), height: CGFloat(mine.height)))
            y -= label
            text(lab, gap, y + 4, size: 12, bold: true)
            y -= gap
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let img = cg.makeImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        try? data.write(to: url)
        return true
    }

    private static func firstRAW(_ args: [String]) -> URL? {
        let exts: Set<String> = ["arw", "cr2", "cr3", "nef", "raf", "rw2", "dng", "orf", "pef"]
        for p in args where !p.hasPrefix("-") {
            let u = URL(fileURLWithPath: p)
            if exts.contains(u.pathExtension.lowercased()), FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}
