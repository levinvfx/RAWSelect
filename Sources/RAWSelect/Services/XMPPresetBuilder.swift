import Foundation

/// Builds a temporary Camera-Raw sidecar `.xmp` for a working-copy RAW, combining
/// an optional user preset with a Smart-Exposure delta. The user's preset file and
/// original RAW/XMP are NEVER modified – output is written only into the temp folder.
enum XMPPresetBuilder {

    /// Returns sidecar XMP text where the exposure is SET to `exposure` (absolute,
    /// authoritative — the preset never controls brightness), based on `presetURL`
    /// if provided (otherwise a minimal default-develop sidecar).
    static func sidecarXMP(presetURL: URL?, evDelta exposure: Double) -> String {
        if let presetURL, let text = try? String(contentsOf: presetURL, encoding: .utf8) {
            return applyExposure(to: text, exposure: exposure)
        }
        return minimalSidecar(evDelta: exposure)
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
