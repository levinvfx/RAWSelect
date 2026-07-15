import Foundation

/// Builds a temporary Camera-Raw sidecar `.xmp` for a working-copy RAW, combining
/// an optional user preset with a Smart-Exposure delta. The user's preset file and
/// original RAW/XMP are NEVER modified – output is written only into the temp folder.
enum XMPPresetBuilder {

    /// Returns sidecar XMP text where the exposure is SET to `exposure` (absolute,
    /// authoritative — the preset never controls brightness), based on `presetURL`
    /// if provided (otherwise a minimal default-develop sidecar).
    static func sidecarXMP(presetURL: URL?, evDelta exposure: Double,
                           edit: ImageEdit? = nil,
                           stripMasks: Bool = false,
                           asShotWB: (temp: Double, tint: Double)? = nil) -> String {
        var text: String
        if let presetURL, var preset = try? String(contentsOf: presetURL, encoding: .utf8) {
            // For the live PREVIEW render we drop all local corrections (AI masks etc.).
            // That renders the global look only – no Lightroom "KI-Updates" dialog and it's
            // faster. The final EXPORT keeps the full preset (stripMasks stays false there).
            if stripMasks { preset = stripLocalCorrections(from: preset) }
            text = applyExposure(to: preset, exposure: exposure)
        } else {
            text = minimalSidecar(evDelta: exposure)
        }
        if let edit { text = applyDevelop(to: text, edit: edit, asShotWB: asShotWB) }
        return text
    }

    /// Removes every local-correction container (AI/brush/gradient masks, retouch) from a
    /// preset's XMP so only the global "look" remains. These blocks are what makes
    /// Lightroom show the "KI-Updates empfohlen" dialog on render. Used for previews only.
    private static func stripLocalCorrections(from xmp: String) -> String {
        var text = xmp
        let blocks = ["MaskGroupBasedCorrections", "GradientBasedCorrections",
                      "CircularGradientBasedCorrections", "PaintBasedCorrections",
                      "RetouchAreas"]
        for b in blocks {
            // Element form: <crs:Block> … </crs:Block> (may span many lines; (?s) = dot matches \n).
            text = text.replacingOccurrences(
                of: "(?s)\\s*<crs:\(b)>.*?</crs:\(b)>", with: "",
                options: .regularExpression)
            // Self-closing / empty form.
            text = text.replacingOccurrences(
                of: "\\s*<crs:\(b)\\s*/>", with: "", options: .regularExpression)
        }
        return text
    }

    /// Injects the Basic-panel develop adjustments as Camera-Raw attributes, for
    /// every non-zero value (exposure is handled separately via `evDelta`). Any
    /// same-named preset attribute is stripped first so the XML stays valid.
    private static func applyDevelop(to xmp: String, edit: ImageEdit,
                                     asShotWB: (temp: Double, tint: Double)?) -> String {
        // Sliders are now shown as PRESET value + user delta. So the exported value is
        // the preset's own value (read from the sidecar) plus the delta — this keeps
        // preview, exact render and export identical.
        var attrs: [(String, Double)] = []
        func add(_ key: String, _ delta: Double) {
            if delta != 0 { attrs.append((key, clamp(key, (value(of: key, in: xmp) ?? 0) + delta))) }
        }
        add("Contrast2012", edit.contrast)
        add("Highlights2012", edit.highlights)
        add("Shadows2012", edit.shadows)
        add("Whites2012", edit.whites)
        add("Blacks2012", edit.blacks)
        // White balance. The slider is a relative nudge (cooler ↔ warmer), but Camera Raw only
        // honours ABSOLUTE Kelvin on a RAW — crs:IncrementalTemperature/-Tint are silently
        // ignored (measured: ±80 changes not a single pixel). So the delta has to be added to
        // a base, and the base has to come from Lightroom.
        //
        // Getting that base is the trick: Lightroom's API reports Temperature only when the
        // white balance is already "Custom"; for "As Shot" it returns nil. Writing Custom
        // WITHOUT a Temperature makes Camera Raw resolve the photo's existing white balance
        // into numbers — same image, but now readable. That first render teaches us the base;
        // every later one adds the delta to it.
        let baseTemp = value(of: "Temperature", in: xmp) ?? asShotWB?.temp
        let baseTint = value(of: "Tint", in: xmp) ?? asShotWB?.tint
        if let baseTemp, let baseTint, edit.temp != 0 || edit.tint != 0 {
            attrs.append(("Temperature", clamp("Temperature", baseTemp + edit.temp)))
            attrs.append(("Tint", clamp("Tint", baseTint + edit.tint)))
        }
        // Color mixer (HSL): each band/channel is a delta over the preset's own value.
        for (k, v) in edit.hsl where v != 0 { attrs.append((k, clamp(k, (value(of: k, in: xmp) ?? 0) + v))) }

        // Custom on EVERY render, even an untouched one: without a Temperature of its own it
        // leaves the picture exactly as it was, but it forces Camera Raw to resolve the white
        // balance into numbers Lightroom will actually hand back to us. That is what makes the
        // very first render usable as the base for the cooler/warmer slider.
        var text = setWhiteBalanceCustom(xmp)
        guard !attrs.isEmpty else { return text }

        for (k, _) in attrs {
            text = text.replacingOccurrences(of: "\\s*crs:\(k)=\"[^\"]*\"", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\s*<crs:\(k)>[^<]*</crs:\(k)>", with: "", options: .regularExpression)
        }
        let ins = attrs.map { " crs:\($0.0)=\"\(Int($0.1.rounded()))\"" }.joined()
        if let r = text.range(of: "<rdf:Description") {
            text.insert(contentsOf: ins, at: r.upperBound)
        }
        return text
    }

    /// Camera Raw's accepted range per control. An out-of-range value is not clamped by ACR —
    /// it is DISCARDED, silently resetting that control to 0, which is the opposite of what the
    /// user asked for. Reachable because a stored delta outlives the preset it was made on:
    /// +80 on a preset with Highlights2012="-87" is a harmless -7, but carry that same delta to
    /// a preset sitting at +50 and it becomes +130 → highlights snap to 0.
    private static func clamp(_ key: String, _ v: Double) -> Double {
        let range: ClosedRange<Double>
        switch key {
        case "Temperature":   range = 2000...50000
        case "Tint":          range = -150...150
        case "Exposure2012":  range = -5...5
        default:              range = -100...100   // Basic panel + all HSL bands
        }
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, v))
    }

    /// Forces crs:WhiteBalance="Custom" (replaces an existing value or inserts one) so an
    /// absolute Temperature/Tint actually takes effect.
    private static func setWhiteBalanceCustom(_ xmp: String) -> String {
        var text = xmp
        if let r = text.range(of: #"crs:WhiteBalance="[^"]*""#, options: .regularExpression) {
            text.replaceSubrange(r, with: "crs:WhiteBalance=\"Custom\"")
        } else if let r = text.range(of: "<rdf:Description") {
            text.insert(contentsOf: " crs:WhiteBalance=\"Custom\"", at: r.upperBound)
        }
        return text
    }

    /// Sets crs:Exposure2012 to the absolute `exposure` value (attribute or element
    /// form), overriding any preset exposure, or inserts one. Everything else in the
    /// preset (the "look") is preserved.
    private static func applyExposure(to xmp: String, exposure: Double) -> String {
        var text = xmp
        // Preset exposure + user delta (see applyDevelop).
        let val = String(format: "%+.2f", (value(of: "Exposure2012", in: xmp) ?? 0) + exposure)

        if let range = text.range(of: #"crs:Exposure2012="([-+]?[0-9]*\.?[0-9]+)""#, options: .regularExpression) {
            text.replaceSubrange(range, with: "crs:Exposure2012=\"\(val)\"")
            return text
        }
        if let range = text.range(of: #"<crs:Exposure2012>([-+]?[0-9]*\.?[0-9]+)</crs:Exposure2012>"#, options: .regularExpression) {
            text.replaceSubrange(range, with: "<crs:Exposure2012>\(val)</crs:Exposure2012>")
            return text
        }
        if let r = text.range(of: "<rdf:Description") {
            text.insert(contentsOf: " crs:Exposure2012=\"\(val)\"", at: r.upperBound)
            return text
        }
        return minimalSidecar(evDelta: exposure)
    }


    /// The Basic-panel develop values a preset sets, so the editor can DISPLAY them
    /// (slider shows preset value + user delta). Keys map to `ImageEdit` fields.
    static func presetValues(_ presetURL: URL?) -> [String: Double] {
        guard let presetURL, let text = try? String(contentsOf: presetURL, encoding: .utf8) else { return [:] }
        let keys = ["Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012",
                    "Blacks2012", "Temperature", "Tint"] + ImageEdit.hslKeys
        var out: [String: Double] = [:]
        for k in keys { if let v = value(of: k, in: text) { out[k] = v } }
        return out
    }

    /// Reads a single crs value (attribute or element form) from XMP text.
    private static func value(of key: String, in text: String) -> Double? {
        for pattern in ["crs:\(key)=\"([-+]?[0-9]*\\.?[0-9]+)\"",
                        "<crs:\(key)>([-+]?[0-9]*\\.?[0-9]+)</crs:\(key)>"] {
            if let re = try? NSRegularExpression(pattern: pattern),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: 1), in: text) {
                return Double(text[r])
            }
        }
        return nil
    }

    private static func minimalSidecar(evDelta: Double) -> String {
        let ev = String(format: "%+.2f", evDelta)
        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            crs:Version="15.0"
            crs:ProcessVersion="15.0"
            crs:Exposure2012="\(ev)"
            crs:HasSettings="True"/>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }
}
