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
                           edit: ImageEdit? = nil, denoise: Double = 0) -> String {
        var text: String
        if let presetURL, let preset = try? String(contentsOf: presetURL, encoding: .utf8) {
            text = applyExposure(to: preset, exposure: exposure)
        } else {
            text = minimalSidecar(evDelta: exposure)
        }
        if let edit { text = applyDevelop(to: text, edit: edit) }
        if denoise > 0 { text = applyDenoise(to: text, amount: denoise) }
        return text
    }

    /// Injects the Basic-panel develop adjustments as Camera-Raw attributes, for
    /// every non-zero value (exposure is handled separately via `evDelta`). Any
    /// same-named preset attribute is stripped first so the XML stays valid.
    private static func applyDevelop(to xmp: String, edit: ImageEdit) -> String {
        var attrs: [(String, Double)] = []
        func add(_ key: String, _ v: Double) { if v != 0 { attrs.append((key, v)) } }
        add("Contrast2012", edit.contrast)
        add("Highlights2012", edit.highlights)
        add("Shadows2012", edit.shadows)
        add("Whites2012", edit.whites)
        add("Blacks2012", edit.blacks)
        add("IncrementalTemperature", edit.temp)
        add("IncrementalTint", edit.tint)
        add("Vibrance", edit.vibrance)
        add("Saturation", edit.saturation)
        add("Clarity2012", edit.clarity)
        add("Sharpness", edit.sharpness)
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
        return text
    }

    /// Sets crs:Exposure2012 to the absolute `exposure` value (attribute or element
    /// form), overriding any preset exposure, or inserts one. Everything else in the
    /// preset (the "look") is preserved.
    private static func applyExposure(to xmp: String, exposure: Double) -> String {
        var text = xmp
        let val = String(format: "%+.2f", exposure)

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
