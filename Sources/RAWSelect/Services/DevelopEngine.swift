import CoreImage

/// Live-preview approximation of the Camera-Raw "Basic" panel. Each adjustment
/// maps to a CoreImage filter so the editor shows an instant preview; the *true*
/// development happens in Adobe on export via the matching `crs:` sidecar values
/// (see `XMPPresetBuilder`). The order roughly mirrors ACR's pipeline.
///
/// This is deliberately an approximation: some controls (positive highlights,
/// crushed blacks) can only be hinted at with CoreImage, but every value is
/// carried faithfully to Adobe for the final render.
enum DevelopEngine {
    /// Tuning factors that map the sliders (Camera-Raw scale) onto the CoreImage
    /// approximation. Kept in ONE place so they can be calibrated against real Adobe
    /// renders (see `--lrsweep`) without hunting through the filter chain. These only
    /// affect the *live drag* preview — the resting image is the exact Adobe render.
    enum Cal {
        // Hand-tuned magnitudes for the live-drag approximation. (An automated MAE-fit
        // against Lightroom renders was tried and reverted: minimising average pixel error
        // with a mismatched filter shape systematically shrank the effects, making the Light
        // preview far too weak. Perceived match ≠ lowest MAE.)
        static var contrast = 0.30         // Contrast2012/100 → S-curve amplitude (mid-tone pivot)
        static var contrastCap = 0.34      // max |S-curve| shift so extreme values stay sane
        static var highlights = 0.13       // Highlights/100 → shift of the 0.75 tone anchor
        static var shadows = 0.13          // Shadows/100    → shift of the 0.25 tone anchor
        static var whites = 0.11           // Whites/100     → extra shift of the 0.75 anchor
        static var blacks = 0.11           // Blacks/100     → extra shift of the 0.25 anchor
        static var exposure = 1.4          // Exposure(EV) → CIExposureAdjust EV multiplier.
                                           // Judged by eye against the real preset render (the neutral
                                           // --expcal metric underestimated the real-world response).
        static var vibrance = 1.0          // Vibrance/100 → CIVibrance amount multiplier
        static var saturation = 1.0        // Saturation/100 → CIColorControls saturation multiplier
        static var hslLum = 0.22           // HSL Luminance ±100 → ±lightness
        static var temp = 1.0              // Temperature delta → CI target-neutral Kelvin scale
        static var tint = 1.0              // Tint delta → CI target-neutral tint scale
        static var clarity = 0.6           // Clarity → unsharp intensity
        static var sharpness = 1.5 / 150   // Sharpness → CISharpenLuminance sharpness
        static var hslHueDeg = 30.0        // HSL Hue ±100 → ±degrees shift
        static var hslSat = 1.0            // HSL Saturation strength multiplier
    }

    static func apply(_ edit: ImageEdit, to base: CIImage) -> CIImage {
        var ci = base

        // White balance. edit.temp/tint are the DELTA (Kelvin / tint units) from the preset,
        // applied over the already-white-balanced preview base — the neutral shift is the
        // delta around CI's default 6500 neutral (delta 0 → no change). The signs are
        // INVERTED versus CITemperatureAndTint's target-neutral convention so the effect
        // matches Camera Raw and the slider gradient: +temp warms (yellow), +tint → magenta.
        // (Measured: raising inputTargetNeutral.x cools, raising .y greens — the opposite.)
        if edit.temp != 0 || edit.tint != 0 {
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500 - edit.temp * Cal.temp, y: -edit.tint * Cal.tint), forKey: "inputTargetNeutral")
            ci = f.outputImage ?? ci
        }

        // Exposure (EV).
        if edit.exposure != 0 {
            let f = CIFilter(name: "CIExposureAdjust")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(edit.exposure * Cal.exposure, forKey: kCIInputEVKey)
            ci = f.outputImage ?? ci
        }

        // Highlights / shadows / whites / blacks as ONE regional tone curve. Shadows+blacks
        // shift the lower anchor (0.25), highlights+whites the upper anchor (0.75); each
        // control responds in BOTH directions (the old CIHighlightShadowAdjust could only
        // darken highlights, and the endpoint-clamped whites/blacks curve did nothing for
        // whites+ / blacks-). Verified correct-signed and visible for every control.
        if edit.highlights != 0 || edit.shadows != 0 || edit.whites != 0 || edit.blacks != 0 {
            func cl(_ y: Double) -> Double { max(0, min(1, y)) }
            let low = edit.shadows / 100 * Cal.shadows + edit.blacks / 100 * Cal.blacks
            let high = edit.highlights / 100 * Cal.highlights + edit.whites / 100 * Cal.whites
            let f = CIFilter(name: "CIToneCurve")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            f.setValue(CIVector(x: 0.25, y: cl(0.25 + low)), forKey: "inputPoint1")
            f.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            f.setValue(CIVector(x: 0.75, y: cl(0.75 + high)), forKey: "inputPoint3")
            f.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
            ci = f.outputImage ?? ci
        }

        // Global saturation.
        if edit.saturation != 0 {
            let f = CIFilter(name: "CIColorControls")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(1 + edit.saturation / 100 * Cal.saturation, forKey: kCIInputSaturationKey)
            ci = f.outputImage ?? ci
        }

        // Contrast as an S-curve around mid-tones — closer to Adobe's Contrast2012
        // (which lifts highlights / drops shadows) than a linear contrast that just
        // scales around grey. Negative contrast flattens the curve.
        if edit.contrast != 0 {
            let k = max(-Cal.contrastCap, min(Cal.contrastCap, edit.contrast / 100 * Cal.contrast))
            let f = CIFilter(name: "CIToneCurve")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            f.setValue(CIVector(x: 0.25, y: 0.25 - k), forKey: "inputPoint1")
            f.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            f.setValue(CIVector(x: 0.75, y: 0.75 + k), forKey: "inputPoint3")
            f.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
            ci = f.outputImage ?? ci
        }

        // Color mixer (HSL): per-hue Hue/Saturation/Luminance via a colour cube, so the
        // Farbmischer has an instant (approximate) live preview. Adobe renders it exactly
        // on export; this only reduces the drag-to-exact jump. Neutrals stay untouched.
        if edit.hsl.values.contains(where: { $0 != 0 }), let cube = hslCube(edit.hsl) {
            cube.setValue(ci, forKey: kCIInputImageKey)
            ci = cube.outputImage ?? ci
        }

        // Vibrance.
        if edit.vibrance != 0 {
            let f = CIFilter(name: "CIVibrance")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(edit.vibrance / 100 * Cal.vibrance, forKey: "inputAmount")
            ci = f.outputImage ?? ci
        }

        // Clarity (local contrast) via a wide-radius unsharp mask.
        if edit.clarity != 0 {
            let f = CIFilter(name: "CIUnsharpMask")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(2.5, forKey: kCIInputRadiusKey)
            f.setValue(edit.clarity / 100 * Cal.clarity, forKey: kCIInputIntensityKey)
            ci = f.outputImage ?? ci
        }

        // Sharpness.
        if edit.sharpness > 0 {
            let f = CIFilter(name: "CISharpenLuminance")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(edit.sharpness * Cal.sharpness, forKey: kCIInputSharpnessKey)
            ci = f.outputImage ?? ci
        }

        // Some filters enlarge the extent (blur kernels) – clamp back to the source.
        return ci.cropped(to: base.extent)
    }

    // MARK: HSL colour cube

    /// Approximate Camera-Raw HSL band centres (degrees on the hue wheel), in the same
    /// order as `ImageEdit.hslBands` (Red…Magenta).
    private static let bandHues: [Double] = [0, 30, 60, 120, 180, 240, 285, 320]

    /// Builds a CIColorCube filter applying the per-band Hue/Saturation/Luminance deltas.
    /// Returns nil if the deltas are all zero.
    private static func hslCube(_ hsl: [String: Double]) -> CIFilter? {
        // Gather per-band deltas (−1…1) for each channel.
        var hue = [Double](repeating: 0, count: 8)
        var sat = [Double](repeating: 0, count: 8)
        var lum = [Double](repeating: 0, count: 8)
        for (i, band) in ImageEdit.hslBands.enumerated() {
            hue[i] = (hsl["HueAdjustment" + band] ?? 0) / 100
            sat[i] = (hsl["SaturationAdjustment" + band] ?? 0) / 100
            lum[i] = (hsl["LuminanceAdjustment" + band] ?? 0) / 100
        }

        let size = 16
        var data = [Float](repeating: 0, count: size * size * size * 4)
        var idx = 0
        let denom = Double(size - 1)
        for bi in 0..<size {
            for gi in 0..<size {
                for ri in 0..<size {
                    let r = Double(ri) / denom, g = Double(gi) / denom, b = Double(bi) / denom
                    var (h, s, l) = rgbToHSL(r, g, b)
                    // Weight the effect by saturation so neutrals stay put.
                    let strength = min(1, s * 2)
                    if strength > 0 {
                        var dHue = 0.0, dSatF = 0.0, dLum = 0.0
                        let w = bandWeights(h)
                        for k in 0..<8 {
                            dHue += w[k] * hue[k] * Cal.hslHueDeg
                            dSatF += w[k] * sat[k] * Cal.hslSat
                            dLum += w[k] * lum[k] * Cal.hslLum
                        }
                        h = h + dHue * strength
                        s = max(0, min(1, s * (1 + dSatF * strength)))
                        l = max(0, min(1, l + dLum * strength))
                    }
                    let (nr, ng, nb) = hslToRGB(h, s, l)
                    data[idx] = Float(nr); data[idx+1] = Float(ng)
                    data[idx+2] = Float(nb); data[idx+3] = 1
                    idx += 4
                }
            }
        }
        let f = CIFilter(name: "CIColorCube")!
        f.setValue(size, forKey: "inputCubeDimension")
        f.setValue(Data(bytes: data, count: data.count * MemoryLayout<Float>.size), forKey: "inputCubeData")
        return f
    }

    /// Triangular hue-band weights (each band influences ±one neighbour), summing to ~1.
    private static func bandWeights(_ hueDeg: Double) -> [Double] {
        var w = [Double](repeating: 0, count: 8)
        var total = 0.0
        for k in 0..<8 {
            var d = abs(hueDeg - bandHues[k])
            if d > 180 { d = 360 - d }
            let span = 60.0   // falloff width
            let ww = max(0, 1 - d / span)
            w[k] = ww; total += ww
        }
        if total > 0 { for k in 0..<8 { w[k] /= total } }
        return w
    }

    private static func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if d > 0 {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
        }
        return (h, s, l)
    }

    private static func hslToRGB(_ hDeg: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        var h = hDeg.truncatingRemainder(dividingBy: 360); if h < 0 { h += 360 }
        if s == 0 { return (l, l, l) }
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<60:   (r1, g1, b1) = (c, x, 0)
        case ..<120:  (r1, g1, b1) = (x, c, 0)
        case ..<180:  (r1, g1, b1) = (0, c, x)
        case ..<240:  (r1, g1, b1) = (0, x, c)
        case ..<300:  (r1, g1, b1) = (x, 0, c)
        default:      (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }
}
