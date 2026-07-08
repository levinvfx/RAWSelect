import SwiftUI
import Combine

// MARK: - Enums shown in the (reduced) settings UI

enum SDBehavior: String, CaseIterable, Identifiable { case notify, autoOpen, ignore
    var id: String { rawValue }
    var label: String { switch self { case .notify: return "Hinweis anzeigen"; case .autoOpen: return "Automatisch öffnen"; case .ignore: return "Ignorieren" } }
}
enum SortField: String, CaseIterable, Identifiable { case filename, captureDate, mark
    var id: String { rawValue }
    var label: String { switch self { case .filename: return "Dateiname"; case .captureDate: return "Aufnahmedatum"; case .mark: return "Markierung" } }
}
enum PreviewMode: String, CaseIterable, Identifiable { case fast, balanced, quality
    var id: String { rawValue }
    var label: String { switch self { case .fast: return "Schnell"; case .balanced: return "Ausgewogen"; case .quality: return "Qualität" } }
    var instantPixels: Int { switch self { case .fast: return 400; case .balanced: return 800; case .quality: return 1200 } }
    var perfectPixels: Int { switch self { case .fast: return 1920; case .balanced: return 2048; case .quality: return 3840 } }
    var preloadForward: Int { switch self { case .fast: return 10; case .balanced: return 20; case .quality: return 30 } }
    var preloadBackward: Int { switch self { case .fast: return 5; case .balanced: return 10; case .quality: return 15 } }
    var maxJobs: Int { switch self { case .fast: return 2; case .balanced: return 3; case .quality: return 4 } }
}
enum RawJpgExport: String, CaseIterable, Identifiable { case both, rawOnly, jpgOnly
    var id: String { rawValue }
    var label: String { switch self { case .both: return "RAW + JPG"; case .rawOnly: return "Nur RAW"; case .jpgOnly: return "Nur JPG" } }
}
enum SmartExposure: String, CaseIterable, Identifiable { case off, soft, standard, strong
    var id: String { rawValue }
    var label: String { switch self { case .off: return "Aus"; case .soft: return "Sanft"; case .standard: return "Standard"; case .strong: return "Stark" } }
}
enum SmartExposureEV: String, CaseIterable, Identifiable { case ev03 = "0.3", ev07 = "0.7", ev10 = "1.0", ev15 = "1.5"
    var id: String { rawValue }
    var label: String { "±\(rawValue) EV" }
    var ev: Double { Double(rawValue) ?? 0.7 }
}

/// Grid thumbnail size, reduced to three clear steps (default medium).
enum ThumbnailSize: String, CaseIterable, Identifiable { case small, medium, large
    var id: String { rawValue }
    var label: String { switch self { case .small: return "Klein"; case .medium: return "Mittel"; case .large: return "Gross" } }
    /// Base cell side in points.
    var px: Double { switch self { case .small: return 110; case .medium: return 150; case .large: return 210 } }
}

/// App appearance, independent of the system setting.
enum AppAppearance: String, CaseIterable, Identifiable { case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: return "System"; case .light: return "Hell"; case .dark: return "Dunkel" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}

enum ConflictMode: String, CaseIterable, Identifiable { case rename, skip, ask, overwrite
    var id: String { rawValue }
    var label: String { switch self { case .rename: return "Automatisch _1, _2, _3 anhängen"; case .skip: return "Überspringen"; case .ask: return "Jedes Mal fragen"; case .overwrite: return "Überschreiben" } }
}

// MARK: - Mark definitions

struct MarkDefinition: Codable, Identifiable, Equatable {
    var id: Int          // 1…9
    var name: String
    var colorHex: String
    var color: Color { Color(hex: colorHex) }

    static let defaults: [MarkDefinition] = [
        .init(id: 1, name: "Red",    colorHex: "#FF222A"),
        .init(id: 2, name: "Yellow", colorHex: "#FBF056"),
        .init(id: 3, name: "Green",  colorHex: "#00F656"),
        .init(id: 4, name: "Blue",   colorHex: "#204EF5"),
        .init(id: 5, name: "Purple", colorHex: "#F73FFA"),
        .init(id: 6, name: "Cyan",   colorHex: "#00FFFF"),
        .init(id: 7, name: "Brown",  colorHex: "#804000"),
        .init(id: 8, name: "Black",  colorHex: "#282828"),
        .init(id: 9, name: "White",  colorHex: "#F9FFEF")
    ]
}

// MARK: - AppSettings store

/// Central, type-safe settings store. Only a small, curated set of options is
/// user-facing (see SettingsView); everything else is a sensible fixed default
/// in code. Kept values are UserDefaults-backed and publish on change.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    let objectWillChange = ObservableObjectPublisher()
    private let d = UserDefaults.standard
    private init() {}

    // Typed accessors
    private func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private func dbl(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
    private func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    private func str(_ k: String, _ def: String) -> String { d.object(forKey: k) as? String ?? def }
    private func en<E: RawRepresentable>(_ k: String, _ def: E) -> E where E.RawValue == String {
        (d.string(forKey: k).flatMap { E(rawValue: $0) }) ?? def
    }
    private func cod<T: Codable>(_ k: String, _ def: T) -> T {
        (d.data(forKey: k).flatMap { try? JSONDecoder().decode(T.self, from: $0) }) ?? def
    }
    private func set(_ k: String, _ v: Any) { objectWillChange.send(); d.set(v, forKey: k) }
    private func setEnum<E: RawRepresentable>(_ k: String, _ v: E) where E.RawValue == String { set(k, v.rawValue) }
    private func setCod<T: Codable>(_ k: String, _ v: T) { if let data = try? JSONEncoder().encode(v) { set(k, data) } }

    // ───────── User-facing settings ─────────

    // Allgemein
    var restoreSession: Bool { get { b("rs.restoreSession", true) } set { set("rs.restoreSession", newValue) } }
    var warnOnQuitDuringOp: Bool { get { b("rs.warnOnQuitDuringOp", true) } set { set("rs.warnOnQuitDuringOp", newValue) } }
    var completionNotification: Bool { get { b("rs.completionNotification", true) } set { set("rs.completionNotification", newValue) } }
    /// Light/Dark/System appearance of the app itself.
    var appearance: AppAppearance { get { en("rs.appearance", .system) } set { setEnum("rs.appearance", newValue) } }

    // Quellen
    var autoDetectVolumes: Bool { get { b("rs.autoDetectVolumes", true) } set { set("rs.autoDetectVolumes", newValue) } }
    var sdBehavior: SDBehavior { get { en("rs.sdBehavior", .notify) } set { setEnum("rs.sdBehavior", newValue) } }

    // Ansicht & Performance
    var thumbnailSizeChoice: ThumbnailSize { get { en("rs.thumbnailSizeChoice", .medium) } set { setEnum("rs.thumbnailSizeChoice", newValue) } }
    /// Grid cell side in points, derived from the three-step size choice.
    var thumbnailSize: Double { thumbnailSizeChoice.px }
    var sortField: SortField { get { en("rs.sortField", .filename) } set { setEnum("rs.sortField", newValue) } }
    var sortReversed: Bool { get { b("rs.sortReversed", false) } set { set("rs.sortReversed", newValue) } }
    var groupRawJpg: Bool { get { b("rs.groupRawJpg", true) } set { set("rs.groupRawJpg", newValue) } }
    var previewMode: PreviewMode { get { en("rs.previewMode", .balanced) } set { setEnum("rs.previewMode", newValue) } }

    // Markierungen
    var autoAdvance: Bool { get { b("rs.autoAdvance", true) } set { set("rs.autoAdvance", newValue) } }
    var marks: [MarkDefinition] { get { cod("rs.marks", MarkDefinition.defaults) } set { setCod("rs.marks", newValue) } }

    // Export
    var revealAfterExport: Bool { get { b("rs.revealAfterExport", true) } set { set("rs.revealAfterExport", newValue) } }
    var rawJpgExport: RawJpgExport { get { en("rs.rawJpgExport", .both) } set { setEnum("rs.rawJpgExport", newValue) } }
    var jpegQualityPercent: Double { get { dbl("rs.jpegQualityPercent", 100) } set { set("rs.jpegQualityPercent", newValue) } }
    var exposureMode: ExposureMode { get { en("rs.exposureMode", .smart) } set { setEnum("rs.exposureMode", newValue) } }
    var smartExposure: SmartExposure { get { en("rs.smartExposure", .standard) } set { setEnum("rs.smartExposure", newValue) } }
    var smartExposureMax: SmartExposureEV { get { en("rs.smartExposureMax", .ev07) } set { setEnum("rs.smartExposureMax", newValue) } }
    /// Noise reduction applied on export (off / Camera-Raw NR / Adobe AI Enhance).
    var denoiseMode: DenoiseMode { get { en("rs.denoiseMode", .off) } set { setEnum("rs.denoiseMode", newValue) } }
    /// Denoise strength 0…100 (default 50).
    var aiDenoiseAmount: Double { get { dbl("rs.aiDenoiseAmount", 50) } set { set("rs.aiDenoiseAmount", newValue) } }

    // Erweitert
    var lightroomPath: String { get { str("rs.lightroomPath", "") } set { set("rs.lightroomPath", newValue) } }
    /// Auto-click Lightroom's "update AI model" / Enhance dialog during export (needs Accessibility permission).
    var autoConfirmLightroomDialogs: Bool { get { b("rs.autoConfirmLightroomDialogs", true) } set { set("rs.autoConfirmLightroomDialogs", newValue) } }
    var presetPath: String { get { str("rs.presetPath", "") } set { set("rs.presetPath", newValue) } }

    // JPEG export (wizard defaults + advanced)
    var colorSpace: ColorSpaceChoice { get { en("rs.colorSpace", .sRGB) } set { setEnum("rs.colorSpace", newValue) } }
    var exportSize: ExportSizeChoice { get { en("rs.exportSize", .original) } set { setEnum("rs.exportSize", newValue) } }
    var customLongEdge: Double { get { dbl("rs.customLongEdge", 4000) } set { set("rs.customLongEdge", newValue) } }
    var deleteTempFiles: Bool { get { b("rs.deleteTempFiles", true) } set { set("rs.deleteTempFiles", newValue) } }
    var rememberPreset: Bool { get { b("rs.rememberPreset", true) } set { set("rs.rememberPreset", newValue) } }
    var recentPresets: [String] { get { cod("rs.recentPresets", []) } set { setCod("rs.recentPresets", newValue) } }
    // Storage keys kept as rs.ps* so existing user values (e.g. last target) survive.
    var exportFolderStructure: ExportFolderStructure { get { en("rs.psFolderStructure", .single) } set { setEnum("rs.psFolderStructure", newValue) } }
    var exportConflict: ConflictMode { get { en("rs.psConflict", .rename) } set { setEnum("rs.psConflict", newValue) } }
    var lastExportTarget: String { get { str("rs.lastPsExportTarget", "") } set { set("rs.lastPsExportTarget", newValue) } }

    /// Adds a preset to the recent list (most recent first, max 5).
    func rememberRecentPreset(_ path: String) {
        guard rememberPreset, !path.isEmpty else { return }
        var list = recentPresets.filter { $0 != path }
        list.insert(path, at: 0)
        recentPresets = Array(list.prefix(5))
    }

    // ───────── Fixed defaults (not shown in UI) ─────────

    // Sources / scanning
    var enabledTypes: [String] { ["arw","cr2","cr3","nef","raf","dng","jpg","jpeg","heic","png"] }
    var recursiveScan: Bool { true }
    var ignoreHidden: Bool { true }
    var cameraFoldersOnly: Bool { true }

    // View / preview badges & behaviour
    var showFilename: Bool { true }
    var showTypeBadge: Bool { true }
    var showMarkBadge: Bool { true }
    var showDateUnderThumb: Bool { false }
    var wrapNavigation: Bool { false }
    var metadataPanel: Bool { true }
    var showMarkToolbar: Bool { true }

    // Preview quality / preloading – derived from previewMode.
    var instantPixels: Int { previewMode.instantPixels }
    var perfectPixels: Int { previewMode.perfectPixels }
    var preloadForward: Double { Double(previewMode.preloadForward) }
    var preloadBackward: Double { Double(previewMode.preloadBackward) }
    var maxParallelJobs: Double { Double(previewMode.maxJobs) }
    var preloadPerfect: Bool { true }

    // Marks behaviour
    var zeroClearsMark: Bool { true }
    var advanceDirection: AdvanceDirection { .next }

    // Export
    var exportSubfolders: Bool { true }
    var useMarkFolderNames: Bool { true }
    var ignoreUnmarked: Bool { true }
    var conflictMode: ConflictMode { .rename }

    // MARK: Derived helpers
    func markDefinition(_ n: Int) -> MarkDefinition {
        marks.first { $0.id == n } ?? MarkDefinition.defaults[max(0, min(8, n - 1))]
    }
    func markColor(_ n: Int) -> Color { markDefinition(n).color }
    func markName(_ n: Int) -> String { markDefinition(n).name }

    /// Subfolder name for a mark on export (format 01_Select), or nil for none.
    func exportFolderName(for mark: Int) -> String? {
        guard exportSubfolders, mark >= 1, mark <= 9 else { return nil }
        return String(format: "%02d_", mark) + sanitize(markName(mark))
    }
    private func sanitize(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }

    /// Preferred color scheme for the whole app (nil = follow system).
    var systemColorScheme: ColorScheme? { appearance.colorScheme }

    func resetAll() {
        objectWillChange.send()
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("rs.") { d.removeObject(forKey: key) }
    }
}

enum AdvanceDirection { case next, previous }

// MARK: - Color <-> hex

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self = Color(red: Double((v >> 16) & 0xff) / 255,
                         green: Double((v >> 8) & 0xff) / 255,
                         blue: Double(v & 0xff) / 255)
        } else { self = .gray }
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        return String(format: "#%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}
