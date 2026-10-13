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

    /// The macOS system palette (the colours Finder tags, Calendar and Reminders use), so the marks
    /// look native next to the rest of the Mac. Positions 1–6 keep their hue from earlier
    /// versions; 7 brown and 8 grey replace the old brown/black (a black badge vanished on dark
    /// photos), and 9 is orange instead of white (white was invisible on the light grid).
    static let defaults: [MarkDefinition] = [
        .init(id: 1, name: "Rot",     colorHex: "#FF3B30"),
        .init(id: 2, name: "Gelb",    colorHex: "#FFCC00"),
        .init(id: 3, name: "Grün",    colorHex: "#34C759"),
        .init(id: 4, name: "Blau",    colorHex: "#007AFF"),
        .init(id: 5, name: "Violett", colorHex: "#AF52DE"),
        .init(id: 6, name: "Türkis",  colorHex: "#5AC8FA"),
        .init(id: 7, name: "Braun",   colorHex: "#A2845E"),
        .init(id: 8, name: "Grau",    colorHex: "#8E8E93"),
        .init(id: 9, name: "Orange",  colorHex: "#FF9500")
    ]

    /// Pre-1.9 defaults were English in an otherwise German UI. Stored settings that still carry
    /// exactly those names are shown in German; custom names are left alone.
    private static let germanNames = ["Red": "Rot", "Yellow": "Gelb", "Green": "Grün", "Blue": "Blau",
                                      "Purple": "Violett", "Cyan": "Türkis", "Brown": "Braun",
                                      "Black": "Schwarz", "White": "Weiss"]
    /// Default colours of V1.0–1.11 (neon). A stored mark that still carries exactly one of these
    /// is an untouched default and follows the new palette; a colour the user picked is kept.
    private static let legacyDefaultHex: Set<String> = ["#FF222A", "#FBF056", "#00F656", "#204EF5",
                                                        "#F73FFA", "#00FFFF", "#804000", "#282828", "#F9FFEF"]
    static func localized(_ m: MarkDefinition) -> MarkDefinition {
        var m = m
        if let de = germanNames[m.name] { m.name = de }
        if legacyDefaultHex.contains(m.colorHex.uppercased()), let fresh = defaults.first(where: { $0.id == m.id }) {
            m.colorHex = fresh.colorHex
            // Name only if it was the old default too (the user may have renamed "Schwarz" to "Kunde").
            if m.name == "Schwarz" || m.name == "Weiss" { m.name = fresh.name }
        }
        return m
    }
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
    var marks: [MarkDefinition] { get { cod("rs.marks", MarkDefinition.defaults).map(MarkDefinition.localized) } set { setCod("rs.marks", newValue) } }

    // Kopieren
    /// After a copy, show the destination folder in the Finder (Erweitert).
    var revealAfterExport: Bool { get { b("rs.revealAfterExport", true) } set { set("rs.revealAfterExport", newValue) } }
    /// Last copy destination — offered again in the folder picker (same target after every game).
    var lastExportTarget: String { get { str("rs.lastPsExportTarget", "") } set { set("rs.lastPsExportTarget", newValue) } }
    /// Recently opened folders on internal disks (cards are listed as volumes anyway), newest first.
    var recentFolders: [String] { get { cod("rs.recentFolders", []) } set { setCod("rs.recentFolders", newValue) } }
    func rememberRecentFolder(_ path: String) {
        var list = recentFolders.filter { $0 != path }
        list.insert(path, at: 0)
        recentFolders = Array(list.prefix(5))
    }
    func forgetRecentFolder(_ path: String) { recentFolders = recentFolders.filter { $0 != path } }

    // Erweitert
    /// App used by the toolbar "In … öffnen" button (Lightroom / Lightroom Classic /
    /// any app). Empty = not yet chosen → picked on first use, then editable here.
    var openWithAppPath: String { get { str("rs.openWithAppPath", "") } set { set("rs.openWithAppPath", newValue) } }

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
    /// Black or white digit — whichever reads better on the mark colour (WCAG contrast), so a
    /// user-picked pastel gets a dark digit and a deep blue a white one.
    func markTextColor(_ n: Int) -> Color { markDefinition(n).color.prefersDarkText ? .black : .white }

    /// Preferred color scheme for the whole app (nil = follow system).
    var systemColorScheme: ColorScheme? { appearance.colorScheme }

    /// Preference keys of settings that no longer exist (collected from the whole git history).
    /// Removed on every launch — idempotent and cheap — so old installs don't carry dead state
    /// forever and a stale value can never resurface if a key name is ever reused.
    private static let obsoleteKeys: [String] = [
        "rs.accent", "rs.accentCustomHex", "rs.advanceDirection", "rs.aiDenoiseAmount",
        "rs.allowDeleteFromSD", "rs.allowMoveFromSD", "rs.appBackground", "rs.autoCleanCache",
        "rs.autoDetectVolumes", "rs.autoManageMemory", "rs.autoScanOnLaunch", "rs.cacheAge",
        "rs.cacheLimit", "rs.cachePath", "rs.cameraFoldersOnly", "rs.cancelStalePreloads",
        "rs.checkerboardTransparency", "rs.clearCacheOnQuit", "rs.closePhotoshopAfter",
        "rs.colorMgmtPreview", "rs.colorMgmtThumbs", "rs.compactToolbar", "rs.completionNotification",
        "rs.conflictMode", "rs.debugLogs", "rs.defaultExportAction", "rs.deleteToTrashOnly",
        "rs.denoiseMode", "rs.detectRawJpgPairs", "rs.enabledTypes", "rs.exportConflict",
        "rs.exportFolderFormat", "rs.exportFolderStructure", "rs.exportSubfolders", "rs.exposureMode",
        "rs.externalAppPath", "rs.fitToPreview", "rs.ignoreHidden", "rs.ignoreUnmarked", "rs.instantFirst",
        "rs.instantQuality", "rs.instantSize", "rs.jpegQuality", "rs.keepFileDates", "rs.lastExportTarget",
        "rs.loadPerfectOnZoom", "rs.maxExternalOpen", "rs.maxParallelJobs", "rs.metadataPanel",
        "rs.perfectAuto", "rs.perfectCache", "rs.perfectQuality", "rs.photoshopAutoDetect",
        "rs.photoshopExport", "rs.photoshopPath", "rs.preloadBackward", "rs.preloadCurrentFilterOnly",
        "rs.preloadForward", "rs.preloadPerfect", "rs.previewBackground", "rs.protectHighlights",
        "rs.protectShadows", "rs.psFolderStructure", "rs.rawJpgExport", "rs.rawJpgOpen", "rs.recursiveScan",
        "rs.reduceMotion", "rs.reducePreloadLowPower", "rs.rememberExportTarget", "rs.rememberLastFolder",
        "rs.rememberWindow", "rs.renameOnExport", "rs.rescanOnFocus", "rs.respectIntentional",
        "rs.respectRotation", "rs.respectScale", "rs.restoreSession", "rs.saveExportLog", "rs.scanMode",
        "rs.sdBehavior", "rs.sendUsageStats", "rs.sessionLocation", "rs.sharpening",
        "rs.showCorrectionBeforeExport", "rs.showDateUnderThumb", "rs.showFilename", "rs.showMarkBadge",
        "rs.showMarkToolbar", "rs.showTypeBadge", "rs.singleMarkPerPhoto", "rs.smartExposure",
        "rs.smartExposureMax", "rs.smoothPreviewSwap", "rs.startBehavior", "rs.stopOnError",
        "rs.storeMarksLocally", "rs.subtleTransitions", "rs.syncPreviewGrid", "rs.thumbnailCache",
        "rs.thumbnailSize", "rs.thumbnailSizeChoice", "rs.usageNoticeShown", "rs.useMarkFolderNames",
        "rs.warnBeforeDelete", "rs.warnBeforeMove", "rs.warnManyExternal", "rs.warnOnQuitDuringOp",
        "rs.warnOnResetMarks", "rs.wrapNavigation", "rs.writeMetadataJpeg", "rs.xmpExport",
        "rs.zeroClearsMark", "rs.zoomWithZ"
    ]

    func removeObsoleteKeys() {
        for key in Self.obsoleteKeys { d.removeObject(forKey: key) }
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("rs.warnSuppress.") {
            d.removeObject(forKey: key)
        }
    }

    func resetAll() {
        objectWillChange.send()
        // Keep the anonymous stats identity: a settings reset is not a new installation, and
        // re-rolling the id would count this Mac twice in the usage numbers.
        let keep: Set<String> = ["rs.anonID", "rs.lastUsagePing", "rs.usageNoticeV2"]
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("rs.") && !keep.contains(key) {
            d.removeObject(forKey: key)
        }
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

    /// Perceived brightness (sRGB luma) — decides whether text on this colour should be black.
    var isLight: Bool {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        return 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent > 0.6
    }

    /// WCAG relative luminance (linear sRGB), the basis for contrast ratios.
    var relativeLuminance: Double {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        func lin(_ c: CGFloat) -> Double { let v = Double(c); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(ns.redComponent) + 0.7152 * lin(ns.greenComponent) + 0.0722 * lin(ns.blueComponent)
    }

    /// White digits wherever they still read (contrast ≥ 3:1, the WCAG floor for bold text), black
    /// only on light colours (yellow, teal, green, orange). Pure "higher ratio wins" would put black
    /// on system blue and grey — technically more contrast, but not how macOS badges look.
    var prefersDarkText: Bool {
        1.05 / (relativeLuminance + 0.05) < 3.0
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        return String(format: "#%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}
