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
    static func apply(_ edit: ImageEdit, to base: CIImage) -> CIImage {
        var ci = base

        // Relative white balance (warm/cool + green/magenta).
        if edit.temp != 0 || edit.tint != 0 {
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500 + edit.temp * 30, y: edit.tint), forKey: "inputTargetNeutral")
            ci = f.outputImage ?? ci
        }

        // Exposure (EV).
        if edit.exposure != 0 {
            let f = CIFilter(name: "CIExposureAdjust")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(edit.exposure, forKey: kCIInputEVKey)
            ci = f.outputImage ?? ci
        }

        // Highlights / shadows recovery.
        if edit.highlights < 0 || edit.shadows != 0 {
            let f = CIFilter(name: "CIHighlightShadowAdjust")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(max(0, min(1, 1 + edit.highlights / 100)), forKey: "inputHighlightAmount")
            f.setValue(max(-1, min(1, edit.shadows / 100)), forKey: "inputShadowAmount")
            ci = f.outputImage ?? ci
        }

        // Whites / blacks via a light tone-curve endpoint shift.
        if edit.whites != 0 || edit.blacks != 0 {
            let f = CIFilter(name: "CIToneCurve")!
            f.setValue(ci, forKey: kCIInputImageKey)
            let w = edit.whites / 100 * 0.15
            let b = edit.blacks / 100 * 0.15
            f.setValue(CIVector(x: 0, y: max(0, b)), forKey: "inputPoint0")
            f.setValue(CIVector(x: 0.25, y: 0.25), forKey: "inputPoint1")
            f.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            f.setValue(CIVector(x: 0.75, y: 0.75), forKey: "inputPoint3")
            f.setValue(CIVector(x: 1, y: min(1, 1 + w)), forKey: "inputPoint4")
            ci = f.outputImage ?? ci
        }

        // Contrast + global saturation.
        if edit.contrast != 0 || edit.saturation != 0 {
            let f = CIFilter(name: "CIColorControls")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(1 + edit.contrast / 100 * 0.5, forKey: kCIInputContrastKey)
            f.setValue(1 + edit.saturation / 100, forKey: kCIInputSaturationKey)
            ci = f.outputImage ?? ci
        }

        // Vibrance.
        if edit.vibrance != 0 {
            let f = CIFilter(name: "CIVibrance")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(edit.vibrance / 100, forKey: "inputAmount")
            ci = f.outputImage ?? ci
        }

        // Clarity (local contrast) via a wide-radius unsharp mask.
        if edit.clarity != 0 {
            let f = CIFilter(name: "CIUnsharpMask")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(2.5, forKey: kCIInputRadiusKey)
            f.setValue(edit.clarity / 100 * 0.6, forKey: kCIInputIntensityKey)
            ci = f.outputImage ?? ci
        }

        // Sharpness.
        if edit.sharpness > 0 {
            let f = CIFilter(name: "CISharpenLuminance")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(edit.sharpness / 150 * 1.5, forKey: kCIInputSharpnessKey)
            ci = f.outputImage ?? ci
        }

        // Some filters enlarge the extent (blur kernels) – clamp back to the source.
        return ci.cropped(to: base.extent)
    }
}
