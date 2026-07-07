import Foundation

// MARK: - Export option enums

enum ColorSpaceChoice: String, CaseIterable, Identifiable { case sRGB, displayP3, adobeRGB
    var id: String { rawValue }
    var label: String { switch self { case .sRGB: return "sRGB"; case .displayP3: return "Display P3"; case .adobeRGB: return "Adobe RGB" } }
    /// Profile name understood by Photoshop's convertProfile.
    var psProfile: String { switch self { case .sRGB: return "sRGB IEC61966-2.1"; case .displayP3: return "Display P3"; case .adobeRGB: return "Adobe RGB (1998)" } }
}

enum ExportSizeChoice: String, CaseIterable, Identifiable { case original, edge3000, edge4000, custom
    var id: String { rawValue }
    var label: String { switch self { case .original: return "Originalgrösse"; case .edge3000: return "Lange Kante 3000 px"; case .edge4000: return "Lange Kante 4000 px"; case .custom: return "Benutzerdefiniert" } }
    /// Long-edge pixel limit, or nil for no resize.
    func longEdge(custom: Int) -> Int? { switch self { case .original: return nil; case .edge3000: return 3000; case .edge4000: return 4000; case .custom: return custom } }
}

enum SharpenChoice: String, CaseIterable, Identifiable { case off, soft, standard
    var id: String { rawValue }
    var label: String { switch self { case .off: return "Aus"; case .soft: return "Sanft"; case .standard: return "Standard" } }
    /// Unsharp-mask amount (%) / radius; 0 = none.
    var amount: Double { switch self { case .off: return 0; case .soft: return 60; case .standard: return 100 } }
    var radius: Double { switch self { case .off: return 0; case .soft: return 0.8; case .standard: return 1.2 } }
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

/// Non-destructive per-image edit applied only for the export.
struct ImageEdit: Equatable {
    /// Clockwise 90° steps: 0, 1, 2, 3.
    var rotation: Int = 0
    /// Fine straighten angle in degrees (clockwise), applied on top of `rotation`.
    var straighten: Double = 0
    /// Crop rectangle in normalised coordinates (0…1) of the rotated+straightened frame; nil = full.
    var crop: CGRect? = nil
    /// Manual exposure (EV) chosen in the live preview; used when ExposureMode == .manual.
    var exposure: Double = 0

    var isIdentity: Bool { rotation == 0 && straighten == 0 && crop == nil && exposure == 0 }
    var totalAngle: Double { Double(rotation) * 90 + straighten }
    mutating func rotateLeft() { rotation = (rotation + 3) % 4 }
    mutating func rotateRight() { rotation = (rotation + 1) % 4 }
}

struct PhotoshopExportItem: Identifiable {
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
    case rendering = "Rendern via Photoshop"
    case saving = "JPEG speichern"
    case done = "Fertig"
    case failed = "Fehlgeschlagen"
}

struct ExportFailure: Identifiable {
    let id = UUID()
    let fileName: String
    let message: String
}
