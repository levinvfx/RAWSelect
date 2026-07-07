import Foundation

/// Builds a temporary Camera-Raw sidecar `.xmp` for a working-copy RAW, combining
/// an optional user preset with a Smart-Exposure delta. The user's preset file and
/// original RAW/XMP are NEVER modified – output is written only into the temp folder.
enum XMPPresetBuilder {

    /// Returns sidecar XMP text for the given exposure delta, based on `presetURL`
    /// if provided (otherwise a minimal default-develop sidecar).
    static func sidecarXMP(presetURL: URL?, evDelta: Double) -> String {
        if let presetURL, let text = try? String(contentsOf: presetURL, encoding: .utf8) {
            return applyExposure(to: text, evDelta: evDelta)
        }
        return minimalSidecar(evDelta: evDelta)
    }

    /// Adds `evDelta` to an existing crs:Exposure2012 value (attribute or element
    /// form), or inserts one. Preserves everything else in the preset.
    private static func applyExposure(to xmp: String, evDelta: Double) -> String {
        guard abs(evDelta) > 0.001 else { return ensureHasSettings(xmp) }
        var text = xmp

        // Attribute form: crs:Exposure2012="+0.10"
        if let range = text.range(of: #"crs:Exposure2012="([-+]?[0-9]*\.?[0-9]+)""#, options: .regularExpression) {
            let match = String(text[range])
            let current = Double(match.replacingOccurrences(of: "crs:Exposure2012=\"", with: "").replacingOccurrences(of: "\"", with: "")) ?? 0
            let newVal = String(format: "crs:Exposure2012=\"%+.2f\"", current + evDelta)
            text.replaceSubrange(range, with: newVal)
            return ensureHasSettings(text)
        }
        // Element form: <crs:Exposure2012>+0.10</crs:Exposure2012>
        if let range = text.range(of: #"<crs:Exposure2012>([-+]?[0-9]*\.?[0-9]+)</crs:Exposure2012>"#, options: .regularExpression) {
            let match = String(text[range])
            let inner = match.replacingOccurrences(of: "<crs:Exposure2012>", with: "").replacingOccurrences(of: "</crs:Exposure2012>", with: "")
            let current = Double(inner) ?? 0
            let newVal = String(format: "<crs:Exposure2012>%+.2f</crs:Exposure2012>", current + evDelta)
            text.replaceSubrange(range, with: newVal)
            return ensureHasSettings(text)
        }
        // No exposure present: inject as attribute on the first rdf:Description.
        if let r = text.range(of: "<rdf:Description") {
            let insertion = " crs:Exposure2012=\"\(String(format: "%+.2f", evDelta))\""
            // Insert right after the tag name.
            let afterTag = text.index(r.upperBound, offsetBy: 0)
            text.insert(contentsOf: insertion, at: afterTag)
            return ensureHasSettings(text)
        }
        return minimalSidecar(evDelta: evDelta)
    }

    private static func ensureHasSettings(_ xmp: String) -> String {
        xmp.contains("crs:HasSettings") ? xmp : xmp
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
