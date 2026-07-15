import Foundation

/// Builds a temporary Camera-Raw sidecar `.xmp` for a working-copy RAW, combining
/// an optional user preset with a Smart-Exposure delta. The user's preset file and
/// original RAW/XMP are NEVER modified – output is written only into the temp folder.
enum XMPPresetBuilder {

    /// Returns sidecar XMP text where the exposure is SET to `exposure` (absolute,
    /// authoritative — the preset never controls brightness), based on `presetURL`
    /// if provided (otherwise a minimal default-develop sidecar). When
    /// `denoise` > 0, Camera-Raw noise reduction is written on top (0…100).
    static func sidecarXMP(presetURL: URL?, evDelta exposure: Double,
                           edit: ImageEdit? = nil, denoise: Double = 0,
                           stripMasks: Bool = false) -> String {
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
        if let edit { text = applyDevelop(to: text, edit: edit) }
        if denoise > 0 { text = applyDenoise(to: text, amount: denoise) }
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
    private static func applyDevelop(to xmp: String, edit: ImageEdit) -> String {
        // Sliders are now shown as PRESET value + user delta. So the exported value is
        // the preset's own value (read from the sidecar) plus the delta — this keeps
        // preview, exact render and export identical.
        var attrs: [(String, Double)] = []
        func add(_ key: String, _ delta: Double) {
            if delta != 0 { attrs.append((key, (value(of: key, in: xmp) ?? 0) + delta)) }
        }
        add("Contrast2012", edit.contrast)
        add("Highlights2012", edit.highlights)
        add("Shadows2012", edit.shadows)
        add("Whites2012", edit.whites)
        add("Blacks2012", edit.blacks)
        // WB is ABSOLUTE (Kelvin): slider shows preset value + delta, so the written value
        // is the preset's own Temperature/Tint plus the delta. Requires WhiteBalance="Custom".
        add("Temperature", edit.temp)
        add("Tint", edit.tint)
        add("Vibrance", edit.vibrance)
        add("Saturation", edit.saturation)
        add("Clarity2012", edit.clarity)
        add("Sharpness", edit.sharpness)
        // Color mixer (HSL): each band/channel is a delta over the preset's own value.
        for (k, v) in edit.hsl where v != 0 { attrs.append((k, (value(of: k, in: xmp) ?? 0) + v)) }
        guard !attrs.isEmpty else { return xmp }

        var text = xmp
        for (k, _) in attrs {
            text = text.replacingOccurrences(of: "\\s*crs:\(k)=\"[^\"]*\"", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\s*<crs:\(k)>[^<]*</crs:\(k)>", with: "", options: .regularExpression)
        }
        let ins = attrs.map { " crs:\($0.0)=\"\(Int($0.1.rounded()))\"" }.joined()
        if let r = text.range(of: "<rdf:Description") {
            text.insert(contentsOf: ins, at: r.upperBound)
        }
        // Absolute WB only applies when the white balance mode is Custom.
        if attrs.contains(where: { $0.0 == "Temperature" || $0.0 == "Tint" }) {
            text = setWhiteBalanceCustom(text)
        }
        return text
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

    /// Writes Camera-Raw noise reduction driven by a single 0…100 strength.
    /// Existing NR attributes/elements from the preset are removed first so the
    /// result stays valid XML (no duplicate keys). Applies to both engines'
    /// render (Lightroom Classic's Camera Raw).
    private static func applyDenoise(to xmp: String, amount: Double) -> String {
        let a = max(0, min(100, amount))
        let luminance = Int(a.rounded())
        let color = Int(min(100, 25 + a * 0.5).rounded())   // gentle chroma NR alongside
        var text = xmp

        // Strip any preset-provided NR so we don't emit duplicate attributes.
        let keys = ["LuminanceSmoothing", "LuminanceNoiseReductionDetail",
                    "LuminanceNoiseReductionContrast", "ColorNoiseReduction",
                    "ColorNoiseReductionDetail", "ColorNoiseReductionSmoothness"]
        for k in keys {
            text = text.replacingOccurrences(of: "\\s*crs:\(k)=\"[^\"]*\"", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\s*<crs:\(k)>[^<]*</crs:\(k)>", with: "", options: .regularExpression)
        }

        let attrs = " crs:LuminanceSmoothing=\"\(luminance)\""
            + " crs:LuminanceNoiseReductionDetail=\"50\""
            + " crs:LuminanceNoiseReductionContrast=\"0\""
            + " crs:ColorNoiseReduction=\"\(color)\""
            + " crs:ColorNoiseReductionDetail=\"50\""
            + " crs:ColorNoiseReductionSmoothness=\"50\""
        if let r = text.range(of: "<rdf:Description") {
            text.insert(contentsOf: attrs, at: r.upperBound)
        }
        return text
    }

    /// The Basic-panel develop values a preset sets, so the editor can DISPLAY them
    /// (slider shows preset value + user delta). Keys map to `ImageEdit` fields.
    static func presetValues(_ presetURL: URL?) -> [String: Double] {
        guard let presetURL, let text = try? String(contentsOf: presetURL, encoding: .utf8) else { return [:] }
        let keys = ["Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012",
                    "Blacks2012", "Vibrance", "Saturation", "Clarity2012", "Sharpness",
                    "Temperature", "Tint"] + ImageEdit.hslKeys
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
