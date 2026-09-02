import SwiftUI
import Combine

// MARK: - Enums shown in the (reduced) settings UI

enum SortField: String, CaseIterable, Identifiable { case filename, captureDate
    var id: String { rawValue }
    var label: String { switch self { case .filename: return "Dateiname"; case .captureDate: return "Dateidatum" } }
}
enum PreviewMode: String, CaseIterable, Identifiable { case fast, balanced, quality
    var id: String { rawValue }
    var label: String { switch self { case .fast: return "Schnell"; case .balanced: return "Ausgewogen"; case .quality: return "Qualität" } }
    var instantPixels: Int { switch self { case .fast: return 400; case .balanced: return 800; case .quality: return 1200 } }
    var perfectPixels: Int { switch self { case .fast: return 1920; case .balanced: return 2048; case .quality: return 3840 } }
    var preloadForward: Int { switch self { case .fast: return 10; case .balanced: return 20; case .quality: return 30 } }
    var preloadBackward: Int { switch self { case .fast: return 5; case .balanced: return 10; case .quality: return 15 } }
    var maxJobs: Int { switch self { case .fast: return 4; case .balanced: return 6; case .quality: return 8 } }
}

/// App appearance, independent of the system setting.
enum AppAppearance: String, CaseIterable, Identifiable { case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: return "System"; case .light: return "Hell"; case .dark: return "Dunkel" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}

/// How a name clash at the destination is handled.
/// There used to be an "ask every time" option here. It never asked — it silently fell
/// through to `rename`. An option that lies is worse than no option.
enum ConflictMode: String, CaseIterable, Identifiable { case rename, skip, overwrite
    var id: String { rawValue }
    var label: String { switch self { case .rename: return "Automatisch _1, _2, _3 anhängen"; case .skip: return "Überspringen"; case .overwrite: return "Überschreiben" } }
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
    /// Light/Dark/System appearance of the app itself.
    var appearance: AppAppearance { get { en("rs.appearance", .system) } set { setEnum("rs.appearance", newValue) } }

    // Ansicht & Performance
    /// Grid thumbnail cell side in points – freely adjustable via the slider
    /// (replaced the earlier three-step choice). Clamped to a sensible range.
    var thumbnailSize: Double {
        get { dbl("rs.thumbnailSizePx", 150) }
        set { set("rs.thumbnailSizePx", min(max(newValue, 90), 320)) }
    }
    var sortField: SortField { get { en("rs.sortField", .filename) } set { setEnum("rs.sortField", newValue) } }
    var sortReversed: Bool { get { b("rs.sortReversed", false) } set { set("rs.sortReversed", newValue) } }
    var groupRawJpg: Bool { get { b("rs.groupRawJpg", true) } set { set("rs.groupRawJpg", newValue) } }
    var previewMode: PreviewMode { get { en("rs.previewMode", .balanced) } set { setEnum("rs.previewMode", newValue) } }

    // Markierungen
    var autoAdvance: Bool { get { b("rs.autoAdvance", true) } set { set("rs.autoAdvance", newValue) } }
    var marks: [MarkDefinition] { get { cod("rs.marks", MarkDefinition.defaults) } set { setCod("rs.marks", newValue) } }

    // Kopieren
    /// After a copy, show the destination folder in the Finder (Erweitert).
    var revealAfterExport: Bool { get { b("rs.revealAfterExport", true) } set { set("rs.revealAfterExport", newValue) } }
    /// Last copy destination — offered again in the folder picker (same target after every game).
    var lastExportTarget: String { get { str("rs.lastPsExportTarget", "") } set { set("rs.lastPsExportTarget", newValue) } }

    // Erweitert
    /// App used by the toolbar "In … öffnen" button (Lightroom / Lightroom Classic /
    /// any app). Empty = not yet chosen → picked on first use, then editable here.
    var openWithAppPath: String { get { str("rs.openWithAppPath", "") } set { set("rs.openWithAppPath", newValue) } }
    /// Anonyme Nutzungsstatistik senden (Opt-out, Standard an). Zählt anonym Version + zufällige
    /// Kennung, keine persönlichen Daten. Siehe `TelemetryService`.
    var sendUsageStats: Bool { get { b("rs.sendUsageStats", true) } set { set("rs.sendUsageStats", newValue) } }

    #if DEBUG
    // ───────── Lightroom export (development builds only) ─────────
    var lightroomPath: String { get { str("rs.lightroomPath", "") } set { set("rs.lightroomPath", newValue) } }
    /// Auto-click Lightroom's "update AI model" / Enhance dialog during export (needs Accessibility permission).
    var autoConfirmLightroomDialogs: Bool { get { b("rs.autoConfirmLightroomDialogs", true) } set { set("rs.autoConfirmLightroomDialogs", newValue) } }
    var presetPath: String { get { str("rs.presetPath", "") } set { set("rs.presetPath", newValue) } }
    var jpegQualityPercent: Double { get { dbl("rs.jpegQualityPercent", 100) } set { set("rs.jpegQualityPercent", newValue) } }
    var colorSpace: ColorSpaceChoice { get { en("rs.colorSpace", .sRGB) } set { setEnum("rs.colorSpace", newValue) } }
    var exportSize: ExportSizeChoice { get { en("rs.exportSize", .original) } set { setEnum("rs.exportSize", newValue) } }
    var customLongEdge: Double { get { dbl("rs.customLongEdge", 4000) } set { set("rs.customLongEdge", newValue) } }
    var deleteTempFiles: Bool { get { b("rs.deleteTempFiles", true) } set { set("rs.deleteTempFiles", newValue) } }
    var rememberPreset: Bool { get { b("rs.rememberPreset", true) } set { set("rs.rememberPreset", newValue) } }
    var recentPresets: [String] { get { cod("rs.recentPresets", []) } set { setCod("rs.recentPresets", newValue) } }
    var exportConflict: ConflictMode { get { en("rs.psConflict", .rename) } set { setEnum("rs.psConflict", newValue) } }

    /// Adds a preset to the recent list (most recent first, max 5).
    func rememberRecentPreset(_ path: String) {
        guard rememberPreset, !path.isEmpty else { return }
        var list = recentPresets.filter { $0 != path }
        list.insert(path, at: 0)
        recentPresets = Array(list.prefix(5))
    }
    #endif

    // ───────── Fixed defaults (not user-facing) ─────────
    // Scanning is always recursive, skips hidden files and prefers DCIM-style folders —
    // these used to be getters that pretended to be settings.

    // Preview quality / preloading – derived from previewMode.
    var instantPixels: Int { previewMode.instantPixels }
    var perfectPixels: Int { previewMode.perfectPixels }
    var preloadForward: Double { Double(previewMode.preloadForward) }
    var preloadBackward: Double { Double(previewMode.preloadBackward) }
    var maxParallelJobs: Double { Double(previewMode.maxJobs) }

    // MARK: Derived helpers
    func markDefinition(_ n: Int) -> MarkDefinition {
        marks.first { $0.id == n } ?? MarkDefinition.defaults[max(0, min(8, n - 1))]
    }
    func markColor(_ n: Int) -> Color { markDefinition(n).color }
    func markName(_ n: Int) -> String { markDefinition(n).name }

    /// Preferred color scheme for the whole app (nil = follow system).
    var systemColorScheme: ColorScheme? { appearance.colorScheme }

    func resetAll() {
        objectWillChange.send()
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("rs.") { d.removeObject(forKey: key) }
    }
}

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
