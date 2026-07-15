import SwiftUI

// MARK: - Export option enums

enum ColorSpaceChoice: String, CaseIterable, Identifiable { case sRGB, displayP3, adobeRGB
    var id: String { rawValue }
    var label: String { switch self { case .sRGB: return "sRGB"; case .displayP3: return "Display P3"; case .adobeRGB: return "Adobe RGB" } }
    /// Export colour space understood by Lightroom (no Display P3 → fall back to sRGB).
    var lrColorSpace: String { switch self { case .sRGB, .displayP3: return "sRGB"; case .adobeRGB: return "AdobeRGB" } }
}

enum ExportSizeChoice: String, CaseIterable, Identifiable { case original, edge3000, edge4000, custom
    var id: String { rawValue }
    var label: String { switch self { case .original: return "Originalgrösse"; case .edge3000: return "Lange Kante 3000 px"; case .edge4000: return "Lange Kante 4000 px"; case .custom: return "Benutzerdefiniert" } }
    /// Long-edge pixel limit, or nil for no resize.
    func longEdge(custom: Int) -> Int? { switch self { case .original: return nil; case .edge3000: return 3000; case .edge4000: return 4000; case .custom: return custom } }
}

/// How noise reduction is applied on export.
/// - noiseReduction: Camera-Raw luminance/chroma NR written to the sidecar
///   (renders immediately, no extra compute).
/// - aiEnhance: Adobe's real AI "Enhance → Denoise" (creates an enhanced DNG).
///   Only reachable via Lightroom + the RAW Select bridge; slower than
///   plain Camera-Raw noise reduction.
enum DenoiseMode: String, CaseIterable, Identifiable { case off, noiseReduction, aiEnhance
    var id: String { rawValue }
    var label: String { switch self {
        case .off: return "Aus"
        case .noiseReduction: return "Rauschreduzierung"
        case .aiEnhance: return "Adobe KI-Denoise (Enhance)" } }
    var isOn: Bool { self != .off }
    var usesEnhance: Bool { self == .aiEnhance }
}


enum ExportFolderStructure: String, CaseIterable, Identifiable { case single, perMark, mirror
    var id: String { rawValue }
    var label: String { switch self { case .single: return "Alle in einen Ordner"; case .perMark: return "Unterordner pro Markierung"; case .mirror: return "Struktur wie Original" } }
}

/// Which photos feed the export.
enum ExportImageSource: Hashable {
    case current, selected, allMarked, filtered
    case mark(Int)
}

// MARK: - Smart Exposure

struct SmartExposureResult: Identifiable {
    var id: String { fileURL.path }
    let fileURL: URL
    let fileName: String
    var averageLuminance: Double = 0    // 0…1
    var medianLuminance: Double = 0
    var p5: Double = 0
    var p95: Double = 0
    var shadowClippingPercent: Double = 0
    var highlightClippingPercent: Double = 0
    var suggestedEV: Double = 0
    var clampedEV: Double = 0
    var confidence: Double = 1
    var notes: String = ""

    var evLabel: String {
        let v = clampedEV
        if abs(v) < 0.02 { return "0.00 EV" }
        return String(format: "%+.2f EV", v)
    }
}

// MARK: - Export job

enum ExposureMode: String, CaseIterable, Identifiable { case smart, manual
    var id: String { rawValue }
    var label: String { self == .smart ? "Smart Exposure" : "Manuelle Belichtung" }
}

/// Non-destructive per-image edit. Held centrally in `AppState.edits` (keyed by
/// group id), persisted per source via `SessionStore`, and applied on export.
struct ImageEdit: Equatable, Codable {
    /// Clockwise 90° steps: 0, 1, 2, 3.
    var rotation: Int = 0
    /// Fine straighten angle in degrees (clockwise), applied on top of `rotation`.
    var straighten: Double = 0
    /// Crop rectangle in normalised coordinates (0…1) of the rotated+straightened frame; nil = full.
    var crop: CGRect? = nil
    /// Manual exposure (EV) chosen in the live preview; used when ExposureMode == .manual.
    var exposure: Double = 0

    // MARK: Develop (Camera-Raw "Basic" panel)
    // All are adjustments around 0 = "no override": only non-zero values are written
    // to the Camera-Raw sidecar, so an applied preset's look stays intact. The live
    // preview is a CoreImage approximation; the true render happens in Adobe on export.
    var contrast: Double = 0     // -100…100 → crs:Contrast2012
    var highlights: Double = 0   // -100…100 → crs:Highlights2012
    var shadows: Double = 0      // -100…100 → crs:Shadows2012
    var whites: Double = 0       // -100…100 → crs:Whites2012
    var blacks: Double = 0       // -100…100 → crs:Blacks2012
    var temp: Double = 0         // Kelvin DELTA from preset → absolute crs:Temperature (WB Custom)
    var tint: Double = 0         // tint DELTA from preset → absolute crs:Tint

    // MARK: Color mixer (HSL) — 8 hue bands × Hue/Saturation/Luminance, each -100…100.
    // Stored as a delta over the preset (like WB): key = full crs key
    // (e.g. "SaturationAdjustmentRed"); only non-zero entries are kept/written.
    var hsl: [String: Double] = [:]

    /// The three Camera-Raw HSL channel prefixes and the eight hue bands.
    static let hslChannels = ["HueAdjustment", "SaturationAdjustment", "LuminanceAdjustment"]
    static let hslBands = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
    /// All 24 crs HSL keys (channel × band).
    static var hslKeys: [String] { hslChannels.flatMap { c in hslBands.map { c + $0 } } }

    /// True when no Basic-panel develop adjustment (besides exposure) is set.
    var developIsZero: Bool {
        contrast == 0 && highlights == 0 && shadows == 0 && whites == 0 && blacks == 0
            && temp == 0 && tint == 0 && hsl.values.allSatisfy { $0 == 0 }
    }

    var isIdentity: Bool {
        rotation == 0 && straighten == 0 && crop == nil && exposure == 0 && developIsZero
    }
    var totalAngle: Double { Double(rotation) * 90 + straighten }
    mutating func rotateLeft() { rotation = (rotation + 3) % 4 }
    mutating func rotateRight() { rotation = (rotation + 1) % 4 }

    /// Stable signature of the tone/develop values that a Lightroom render depends on
    /// (exposure + Basic panel). Excludes crop/rotate/straighten — those are applied
    /// locally, not baked by the render. Used to key the exact preset-preview cache.
    var developSignature: String {
        let basic = [exposure, contrast, highlights, shadows, whites, blacks, temp, tint]
            .map { String(format: "%.3f", $0) }.joined(separator: ",")
        let color = hsl.filter { $0.value != 0 }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(String(format: "%.3f", $0.value))" }.joined(separator: ",")
        return color.isEmpty ? basic : basic + ";hsl:" + color
    }
}

struct ExportItem: Identifiable {
    var id: String { rawURL.path }
    let group: PhotoGroup
    let rawURL: URL          // the file to develop (RAW preferred)
    var evDelta: Double = 0  // absolute exposure applied in ACR (Smart or Manual)
    var edit: ImageEdit = ImageEdit()
}

enum ExportStage: String {
    case preparing = "Vorbereiten"
    case analyzing = "Belichtung analysieren"
    case applyingPreset = "Preset anwenden"
    case rendering = "Rendern"
    case saving = "JPEG speichern"
    case done = "Fertig"
    case failed = "Fehlgeschlagen"
}

struct ExportFailure: Identifiable {
    let id = UUID()
    let fileName: String
    let message: String
}
