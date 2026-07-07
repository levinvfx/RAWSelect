import Foundation
import CoreGraphics
import ImageIO

/// Computes a gentle per-image exposure correction from LOCAL image statistics
/// only – histogram, mean/median luminance, shadow/highlight clipping. No AI, no
/// cloud, no network. Works on a small downscaled preview for speed.
struct SmartExposureAnalyzer {

    struct Config {
        var strength: SmartExposure = .standard   // off/soft/standard/strong
        var maxEV: Double = 0.7
        var protectHighlights = true
        var protectShadows = true
        var respectIntentional = true
    }

    /// Middle-grey target in sRGB (linear 0.18 ≈ sRGB 0.46).
    private static let targetMedianSRGB = 0.46

    static func analyze(url: URL, config: Config) -> SmartExposureResult {
        var result = SmartExposureResult(fileURL: url, fileName: url.lastPathComponent)
        guard config.strength != .off else { result.notes = "Aus"; return result }

        guard let hist = luminanceHistogram(url: url) else {
            result.notes = "Keine Preview – 0 EV"
            return result
        }

        let total = max(1, hist.reduce(0, +))
        // Percentiles / stats over the 256-bin histogram (bin i ≈ value i/255).
        func value(atCumulative fraction: Double) -> Double {
            let target = Double(total) * fraction
            var acc = 0
            for i in 0..<256 { acc += hist[i]; if Double(acc) >= target { return Double(i) / 255.0 } }
            return 1.0
        }
        var weightedSum = 0.0
        for i in 0..<256 { weightedSum += Double(i) / 255.0 * Double(hist[i]) }

        result.averageLuminance = weightedSum / Double(total)
        result.medianLuminance = value(atCumulative: 0.5)
        result.p5 = value(atCumulative: 0.05)
        result.p95 = value(atCumulative: 0.95)
        // Clipping: pixels within the extreme few bins.
        let shadow = hist[0...4].reduce(0, +)
        let highlight = hist[251...255].reduce(0, +)
        result.shadowClippingPercent = Double(shadow) / Double(total) * 100
        result.highlightClippingPercent = Double(highlight) / Double(total) * 100

        // Suggested EV from median vs target, computed in linear light.
        let mLin = srgbToLinear(max(result.medianLuminance, 0.002))
        let tLin = srgbToLinear(targetMedianSRGB)
        var ev = log2(tLin / mLin)

        // Protect highlights: don't brighten into clipping.
        if config.protectHighlights && ev > 0 {
            if result.highlightClippingPercent > 2 { ev = 0 }
            else if result.p95 > 0.92 { ev = min(ev, 0.2) }
        }
        // Protect shadows: be cautious darkening an already-dark frame.
        if config.protectShadows && ev < 0 && result.shadowClippingPercent > 8 {
            ev *= 0.4
        }
        // Respect intentionally low-key / high-key images.
        var confidence = 1.0
        if config.respectIntentional {
            if result.medianLuminance < 0.12 || result.medianLuminance > 0.85 {
                ev *= 0.4; confidence = 0.5
                result.notes = "Absichtlich dunkel/hell – vorsichtig"
            }
        }

        // Strength scaling.
        switch config.strength {
        case .off: ev = 0
        case .soft: ev *= 0.5
        case .standard: break
        case .strong: ev *= 1.3
        }

        result.suggestedEV = ev
        result.clampedEV = max(-config.maxEV, min(config.maxEV, ev))
        result.confidence = confidence
        if result.notes.isEmpty {
            result.notes = abs(result.clampedEV) < 0.02 ? "Gut belichtet" : "Korrigiert"
        }
        return result
    }

    // MARK: - Pixel stats

    /// 256-bin luminance histogram from a small decoded preview.
    private static func luminanceHistogram(url: URL, maxPixel: Int = 400) -> [Int]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }

        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var hist = [Int](repeating: 0, count: 256)
        var i = 0
        let count = w * h
        while i < count {
            let o = i * 4
            let r = Double(buffer[o]), g = Double(buffer[o + 1]), b = Double(buffer[o + 2])
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b   // 0…255
            hist[min(255, max(0, Int(lum)))] += 1
            i += 1
        }
        return hist
    }

    private static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
