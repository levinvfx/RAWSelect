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
        static var contrast = 0.17         // Contrast2012/100 → S-curve amplitude (mid-tone pivot)
        static var contrastCap = 0.34      // max |S-curve| shift so extreme values stay sane
        // Fitted to Lightroom renders via `--slidercal`; see the tone curve below.
        static var highlights = 0.14       // Highlights/100 → peak curve lift around x≈0.85
        static var shadows = 0.09          // Shadows/100    → peak curve lift around x≈0.15
        // Whites and Blacks are ASYMMETRIC in Camera Raw — measured, not assumed. Pushing them
        // up scales the image and clips; pulling them down only compresses one end. Each
        // direction also ACCELERATES (Adobe's Whites ran +20/+40/+80 → 1 : 2 : 9), so the
        // slider value is raised to a power instead of scaling linearly.
        static var whitesPos = 0.29        // Whites+ → white point pulled in (lift + clipping)
        static var whitesNeg = 0.10        // Whites− → top-end compression only
        static var blacksPos = 0.15        // Blacks+ → black point lifted
        static var blacksNeg = 0.31        // Blacks− → black point pulled in (crush)
        static var whitesPosExp = 1.6      // curvature of the Whites+ response (clipping ramp)
        static var whitesNegExp = 1.0      // Whites− stays linear — it never clips
        static var blacksPosExp = 1.25
        static var blacksNegExp = 1.2
        static var exposure = 1.4          // Exposure(EV) → CIExposureAdjust EV multiplier.
                                           // Judged by eye against the real preset render.
        static var hslLum = 0.65           // HSL Luminance ±100 → ±lightness
        // Even anchored at the real Kelvin, CoreImage moves less than Camera Raw, and less
        // still when cooling than when warming — hence one factor per direction.
        static var tempCool = 2.6          // Temperature− → CI target-neutral Kelvin scale
        static var tempWarm = 1.35         // Temperature+ → CI target-neutral Kelvin scale
        static var tint = 1.33             // Tint delta → CI target-neutral tint scale
        static var hslHueDeg = 90.0        // HSL Hue ±100 → ±degrees shift
        static var hslSatPos = 3.5         // HSL Saturation+ → RGB chroma scale (clips like ACR)
        static var hslSatNeg = 2.0         // HSL Saturation− → scales `s` in HSL
    }

    /// `wbBase` is the Kelvin the picture currently sits at (the RAW's as-shot value, or the
    /// preset's own). The white-balance preview needs it because colour temperature is
    /// RECIPROCAL: −1200 K from 5500 is a far bigger colour shift than +1200 K. Anchoring at a
    /// fixed 6500 made the preview both too weak and lopsided (measured 0.22× of Adobe when
    /// cooling, 0.62× when warming). Anchoring at the real value lets CoreImage do that
    /// non-linear maths itself. The default is daylight, for when it isn't known yet.
    static func apply(_ edit: ImageEdit, to base: CIImage, wbBase: Double = 5500) -> CIImage {
        var ci = base

        // White balance. edit.temp/tint are the DELTA (Kelvin / tint units) from the base.
        // The signs are INVERTED versus CITemperatureAndTint's target-neutral convention so the
        // effect matches Camera Raw and the slider gradient: +temp warms (yellow), +tint →
        // magenta. (Measured: raising inputTargetNeutral.x cools, raising .y greens.)
        if edit.temp != 0 || edit.tint != 0 {
            let anchor = max(2000, min(50000, wbBase))
            let cal = edit.temp > 0 ? Cal.tempWarm : Cal.tempCool
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: anchor, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: max(2000, min(50000, anchor - edit.temp * cal)),
                                y: -edit.tint * Cal.tint), forKey: "inputTargetNeutral")
            ci = f.outputImage ?? ci
        }

        // Exposure (EV).
        if edit.exposure != 0 {
            let f = CIFilter(name: "CIExposureAdjust")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(edit.exposure * Cal.exposure, forKey: kCIInputEVKey)
            ci = f.outputImage ?? ci
        }

        // Highlights / shadows / whites / blacks as ONE tone curve. Each control is a broad
        // Gaussian bump whose centre, width and amplitude were fitted against real Lightroom
        // renders (`--slidercal`): Camera Raw's tone controls reach much further than their
        // name suggests — Whites and Highlights lift the MID-tones nearly as much as the top,
        // and Blacks pulls the mids down harder than the shadows themselves.
        //
        // The previous curve pinned the 0.5 anchor and only moved the 0.25/0.75 points, so the
        // mid-tones could never follow: Whites came out ~10× too weak (ratio 0.09 vs Adobe) and
        // no amount of scaling could fix it, because the SHAPE — not the strength — was wrong.
        // Whites and Blacks move the white/black POINT, the way Camera Raw does — that is why
        // their response is asymmetric and accelerating rather than linear: pulling the white
        // point inward makes more and more pixels clip. Measured on a real render, Whites −66
        // barely moved the image while +80 lifted it enormously (a 1 : 2 : 9 progression).
        // Modelled as a symmetric bump instead, the negative side came out 3–5× too strong.
        //
        // Highlights and Shadows bend the curve between those endpoints as broad Gaussian
        // bumps — broad because Camera Raw's tone controls reach well into the mid-tones.
        if edit.highlights != 0 || edit.shadows != 0 || edit.whites != 0 || edit.blacks != 0 {
            /// Slider → curve amount, accelerating like Camera Raw's own response.
            func shaped(_ v: Double, _ cal: Double, _ e: Double) -> Double {
                min(0.45, pow(abs(v) / 100, e) * cal)
            }
            func bump(_ x: Double, _ centre: Double, _ sigma: Double) -> Double {
                let t = (x - centre) / sigma
                return exp(-t * t)
            }
            let whiteIn = edit.whites > 0 ? shaped(edit.whites, Cal.whitesPos, Cal.whitesPosExp) : 0
            let whiteDown = edit.whites < 0 ? shaped(edit.whites, Cal.whitesNeg, Cal.whitesNegExp) : 0
            let blackLift = edit.blacks > 0 ? shaped(edit.blacks, Cal.blacksPos, Cal.blacksPosExp) : 0
            let blackIn = edit.blacks < 0 ? shaped(edit.blacks, Cal.blacksNeg, Cal.blacksNegExp) : 0

            func y(_ x: Double) -> Double {
                var v = x
                // Blacks move the black point: + lifts it off zero, − pulls it in and crushes.
                if blackLift > 0 { v = blackLift + v * (1 - blackLift) }
                if blackIn > 0 { v = (v - blackIn) / (1 - blackIn) }
                // Whites+ scales the whole curve up until the top clips — that global lift is
                // what Adobe does. Whites− does NOT scale globally; it only rolls the top off,
                // which is why its measured effect on shadows was nearly nil.
                if whiteIn > 0 { v /= (1 - whiteIn) }
                if whiteDown > 0 { v -= whiteDown * bump(x, 1.0, 0.40) }
                v += edit.shadows    / 100 * Cal.shadows    * bump(x, 0.15, 0.50)
                v += edit.highlights / 100 * Cal.highlights * bump(x, 0.85, 0.50)
                return max(0, min(1, v))
            }
            let f = CIFilter(name: "CIToneCurve")!
            f.setValue(ci, forKey: kCIInputImageKey)
            for (i, x) in [0.0, 0.25, 0.5, 0.75, 1.0].enumerated() {
                f.setValue(CIVector(x: x, y: y(x)), forKey: "inputPoint\(i)")
            }
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
                    // Protect neutrals, but only neutrals: `s * 2` still halved the effect on
                    // ordinary colours (a blue sky sits around s≈0.3), and combined with the
                    // hue-band blend that left the mixer 2–7× weaker than Camera Raw.
                    let strength = min(1, s * 4)
                    var dSat = 0.0
                    if strength > 0 {
                        var dHue = 0.0, dLum = 0.0
                        let w = bandWeights(h)
                        for k in 0..<8 {
                            dHue += w[k] * hue[k] * Cal.hslHueDeg
                            dSat += w[k] * sat[k]
                            dLum += w[k] * lum[k] * Cal.hslLum
                        }
                        h = h + dHue * strength
                        l = max(0, min(1, l + dLum * strength))
                    }
                    // Saturation is handled differently per direction, because measurement says
                    // the two behave differently and no single model fit both:
                    //  − : scaling `s` in HSL tracks Adobe closely (ratio ≈ 0.85).
                    //  + : scaling `s` hits the ceiling at s = 1 and stalls at ~1/3 of Adobe's
                    //      effect, so chroma is scaled in RGB instead, which clips the way
                    //      Camera Raw does.
                    if dSat < 0 { s = max(0, min(1, s * (1 + dSat * Cal.hslSatNeg * strength))) }
                    var (nr, ng, nb) = hslToRGB(h, s, l)
                    if dSat > 0 {
                        let f = 1 + dSat * Cal.hslSatPos * strength
                        let y = 0.299 * nr + 0.587 * ng + 0.114 * nb
                        nr = max(0, min(1, y + (nr - y) * f))
                        ng = max(0, min(1, y + (ng - y) * f))
                        nb = max(0, min(1, y + (nb - y) * f))
                    }
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
