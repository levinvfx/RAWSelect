import SwiftUI
import Combine

// MARK: - Enums for pickers

enum StartBehavior: String, CaseIterable, Identifiable { case startScreen, lastSession, lastFolder, emptyWindow
    var id: String { rawValue }
    var label: String { switch self {
        case .startScreen: return "Startscreen anzeigen"
        case .lastSession: return "Letzte Session öffnen"
        case .lastFolder: return "Letzten Ordner automatisch öffnen"
        case .emptyWindow: return "Leeres Fenster öffnen" } }
}
enum SDBehavior: String, CaseIterable, Identifiable { case notify, autoOpen, ignore
    var id: String { rawValue }
    var label: String { switch self { case .notify: return "Hinweis anzeigen"; case .autoOpen: return "Automatisch öffnen"; case .ignore: return "Ignorieren" } }
}
enum ScanMode: String, CaseIterable, Identifiable { case fast, normal, full
    var id: String { rawValue }
    var label: String { switch self { case .fast: return "Schnell: Nur Kameraordner"; case .normal: return "Normal: Ausgewählter Ordner rekursiv"; case .full: return "Vollständig: Gesamten Datenträger scannen" } }
}
enum SortField: String, CaseIterable, Identifiable { case filename, captureDate, modifiedDate, mark, type
    var id: String { rawValue }
    var label: String { switch self { case .filename: return "Dateiname"; case .captureDate: return "Aufnahmedatum"; case .modifiedDate: return "Änderungsdatum"; case .mark: return "Markierung"; case .type: return "Dateityp" } }
}
enum InstantSize: String, CaseIterable, Identifiable { case px400 = "400", px800 = "800", px1200 = "1200", px1600 = "1600"
    var id: String { rawValue }
    var pixels: Int { Int(rawValue) ?? 800 }
    var label: String { "\(rawValue) px" }
}
enum QualityLevel: String, CaseIterable, Identifiable { case low, medium, high
    var id: String { rawValue }
    var label: String { switch self { case .low: return "Niedrig"; case .medium: return "Mittel"; case .high: return "Hoch" } }
}
enum PerfectQuality: String, CaseIterable, Identifiable { case fullHD, screen, uhd4k
    var id: String { rawValue }
    var label: String { switch self { case .fullHD: return "Full HD"; case .screen: return "Bildschirmoptimiert, mind. Full HD"; case .uhd4k: return "4K" } }
}
enum AdvanceDirection: String, CaseIterable, Identifiable { case next, previous
    var id: String { rawValue }
    var label: String { self == .next ? "Nächstes Bild" : "Vorheriges Bild" }
}
enum DefaultExportAction: String, CaseIterable, Identifiable { case copy, move
    var id: String { rawValue }
    var label: String { self == .copy ? "Kopieren" : "Verschieben" }
}
enum ExportFolderFormat: String, CaseIterable, Identifiable { case numberName, numberMark, name, single
    var id: String { rawValue }
    var label: String { switch self { case .numberName: return "01_Select"; case .numberMark: return "01_Mark_1"; case .name: return "Select"; case .single: return "Alles in einen Ordner" } }
}
enum RawJpgExport: String, CaseIterable, Identifiable { case both, rawOnly, jpgOnly, ask
    var id: String { rawValue }
    var label: String { switch self { case .both: return "RAW + JPG kopieren"; case .rawOnly: return "Nur RAW kopieren"; case .jpgOnly: return "Nur JPG kopieren"; case .ask: return "Jedes Mal fragen" } }
}
enum RawJpgOpen: String, CaseIterable, Identifiable { case raw, jpg, ask
    var id: String { rawValue }
    var label: String { switch self { case .raw: return "RAW öffnen"; case .jpg: return "JPG öffnen"; case .ask: return "Jedes Mal fragen" } }
}
enum ConflictMode: String, CaseIterable, Identifiable { case rename, skip, ask, overwrite
    var id: String { rawValue }
    var label: String { switch self { case .rename: return "Automatisch _1, _2, _3 anhängen"; case .skip: return "Überspringen"; case .ask: return "Jedes Mal fragen"; case .overwrite: return "Überschreiben" } }
}
enum AppearanceMode: String, CaseIterable, Identifiable { case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: return "System"; case .light: return "Hell"; case .dark: return "Dunkel" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}
enum AppBackground: String, CaseIterable, Identifiable { case system, light, dark, softWhite
    var id: String { rawValue }
    var label: String { switch self { case .system: return "System"; case .light: return "Hell"; case .dark: return "Dunkel"; case .softWhite: return "Sanftes Weiss" } }
}
enum PreviewBackground: String, CaseIterable, Identifiable { case system, dark, light, neutralGray
    var id: String { rawValue }
    var label: String { switch self { case .system: return "System"; case .dark: return "Dunkel"; case .light: return "Hell"; case .neutralGray: return "Neutralgrau" } }
    var color: Color { switch self {
        case .system: return Color(nsColor: .textBackgroundColor).opacity(0.4)
        case .dark: return Color(white: 0.12)
        case .light: return Color(white: 0.95)
        case .neutralGray: return Color(white: 0.5) } }
}
enum AccentChoice: String, CaseIterable, Identifiable { case system, blue, graphite, custom
    var id: String { rawValue }
    var label: String { switch self { case .system: return "System"; case .blue: return "Blau"; case .graphite: return "Graphit"; case .custom: return "Eigene Farbe" } }
}
enum CacheLimit: String, CaseIterable, Identifiable { case gb1 = "1", gb5 = "5", gb10 = "10", gb20 = "20"
    var id: String { rawValue }
    var label: String { "\(rawValue) GB" }
}
enum CacheAge: String, CaseIterable, Identifiable { case d7 = "7", d30 = "30", d60 = "60", d90 = "90"
    var id: String { rawValue }
    var label: String { "\(rawValue) Tage" }
}
enum SessionLocation: String, CaseIterable, Identifiable { case appStorage, sidecar
    var id: String { rawValue }
    var label: String { self == .appStorage ? "App-Speicher" : "Session-Datei im Bildordner" }
}

// MARK: - Mark definitions

struct MarkDefinition: Codable, Identifiable, Equatable {
    var id: Int          // 1…9
    var name: String
    var colorHex: String
    var color: Color { Color(hex: colorHex) }

    static let defaults: [MarkDefinition] = [
        .init(id: 1, name: "Select",  colorHex: "#3B82F6"),
        .init(id: 2, name: "Edit",    colorHex: "#F59E0B"),
        .init(id: 3, name: "Client",  colorHex: "#34C759"),
        .init(id: 4, name: "Social",  colorHex: "#FF2D9B"),
        .init(id: 5, name: "Website", colorHex: "#30C0C6"),
        .init(id: 6, name: "Maybe",   colorHex: "#FFD60A"),
        .init(id: 7, name: "Story",   colorHex: "#7C4DFF"),
        .init(id: 8, name: "Archive", colorHex: "#8E8E93"),
        .init(id: 9, name: "Reject",  colorHex: "#FF3B30")
    ]
}

// MARK: - AppSettings store

/// Central, type-safe, persistent settings store (UserDefaults-backed). Computed
/// properties publish on change so `$settings.x` bindings update the UI live.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    let objectWillChange = ObservableObjectPublisher()
    private let d = UserDefaults.standard
    private init() {}

    // Typed accessors
    private func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private func dbl(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
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

    // 1 – Allgemein
    var startBehavior: StartBehavior { get { en("rs.startBehavior", .startScreen) } set { setEnum("rs.startBehavior", newValue) } }
    var restoreSession: Bool { get { b("rs.restoreSession", true) } set { set("rs.restoreSession", newValue) } }
    var rememberLastFolder: Bool { get { b("rs.rememberLastFolder", true) } set { set("rs.rememberLastFolder", newValue) } }
    var rememberWindow: Bool { get { b("rs.rememberWindow", true) } set { set("rs.rememberWindow", newValue) } }
    var autoScanOnLaunch: Bool { get { b("rs.autoScanOnLaunch", false) } set { set("rs.autoScanOnLaunch", newValue) } }
    var warnOnQuitDuringOp: Bool { get { b("rs.warnOnQuitDuringOp", true) } set { set("rs.warnOnQuitDuringOp", newValue) } }
    var completionNotification: Bool { get { b("rs.completionNotification", true) } set { set("rs.completionNotification", newValue) } }

    // 2 – Quellen
    var autoDetectVolumes: Bool { get { b("rs.autoDetectVolumes", true) } set { set("rs.autoDetectVolumes", newValue) } }
    var sdBehavior: SDBehavior { get { en("rs.sdBehavior", .notify) } set { setEnum("rs.sdBehavior", newValue) } }
    var cameraFoldersOnly: Bool { get { b("rs.cameraFoldersOnly", true) } set { set("rs.cameraFoldersOnly", newValue) } }
    var recursiveScan: Bool { get { b("rs.recursiveScan", true) } set { set("rs.recursiveScan", newValue) } }
    var ignoreHidden: Bool { get { b("rs.ignoreHidden", true) } set { set("rs.ignoreHidden", newValue) } }
    var rescanOnFocus: Bool { get { b("rs.rescanOnFocus", true) } set { set("rs.rescanOnFocus", newValue) } }
    var scanMode: ScanMode { get { en("rs.scanMode", .fast) } set { setEnum("rs.scanMode", newValue) } }
    var enabledTypes: [String] {
        get { cod("rs.enabledTypes", ["arw","cr2","cr3","nef","raf","dng","jpg","jpeg","heic","png"]) }
        set { setCod("rs.enabledTypes", newValue) }
    }

    // 3 – Ansicht & Preview
    var thumbnailSize: Double { get { dbl("rs.thumbnailSize", 128) } set { set("rs.thumbnailSize", newValue) } }
    var sortField: SortField { get { en("rs.sortField", .filename) } set { setEnum("rs.sortField", newValue) } }
    var sortReversed: Bool { get { b("rs.sortReversed", false) } set { set("rs.sortReversed", newValue) } }
    var showFilename: Bool { get { b("rs.showFilename", true) } set { set("rs.showFilename", newValue) } }
    var showTypeBadge: Bool { get { b("rs.showTypeBadge", true) } set { set("rs.showTypeBadge", newValue) } }
    var showMarkBadge: Bool { get { b("rs.showMarkBadge", true) } set { set("rs.showMarkBadge", newValue) } }
    var showDateUnderThumb: Bool { get { b("rs.showDateUnderThumb", false) } set { set("rs.showDateUnderThumb", newValue) } }
    var groupRawJpg: Bool { get { b("rs.groupRawJpg", true) } set { set("rs.groupRawJpg", newValue) } }
    var fitToPreview: Bool { get { b("rs.fitToPreview", true) } set { set("rs.fitToPreview", newValue) } }
    var respectRotation: Bool { get { b("rs.respectRotation", true) } set { set("rs.respectRotation", newValue) } }
    var syncPreviewGrid: Bool { get { b("rs.syncPreviewGrid", true) } set { set("rs.syncPreviewGrid", newValue) } }
    var wrapNavigation: Bool { get { b("rs.wrapNavigation", false) } set { set("rs.wrapNavigation", newValue) } }
    var zoomWithZ: Bool { get { b("rs.zoomWithZ", true) } set { set("rs.zoomWithZ", newValue) } }
    var loadPerfectOnZoom: Bool { get { b("rs.loadPerfectOnZoom", true) } set { set("rs.loadPerfectOnZoom", newValue) } }
    var instantFirst: Bool { get { b("rs.instantFirst", true) } set { set("rs.instantFirst", newValue) } }
    var instantSize: InstantSize { get { en("rs.instantSize", .px800) } set { setEnum("rs.instantSize", newValue) } }
    var instantQuality: QualityLevel { get { en("rs.instantQuality", .medium) } set { setEnum("rs.instantQuality", newValue) } }
    var perfectAuto: Bool { get { b("rs.perfectAuto", true) } set { set("rs.perfectAuto", newValue) } }
    var perfectQuality: PerfectQuality { get { en("rs.perfectQuality", .screen) } set { setEnum("rs.perfectQuality", newValue) } }
    var respectScale: Bool { get { b("rs.respectScale", true) } set { set("rs.respectScale", newValue) } }
    var smoothPreviewSwap: Bool { get { b("rs.smoothPreviewSwap", true) } set { set("rs.smoothPreviewSwap", newValue) } }

    // 4 – Markierungen
    var singleMarkPerPhoto: Bool { get { b("rs.singleMarkPerPhoto", true) } set { set("rs.singleMarkPerPhoto", newValue) } }
    var zeroClearsMark: Bool { get { b("rs.zeroClearsMark", true) } set { set("rs.zeroClearsMark", newValue) } }
    var autoAdvance: Bool { get { b("rs.autoAdvance", true) } set { set("rs.autoAdvance", newValue) } }
    var advanceDirection: AdvanceDirection { get { en("rs.advanceDirection", .next) } set { setEnum("rs.advanceDirection", newValue) } }
    var storeMarksLocally: Bool { get { b("rs.storeMarksLocally", true) } set { set("rs.storeMarksLocally", newValue) } }
    var showMarkToolbar: Bool { get { b("rs.showMarkToolbar", true) } set { set("rs.showMarkToolbar", newValue) } }
    var warnOnResetMarks: Bool { get { b("rs.warnOnResetMarks", true) } set { set("rs.warnOnResetMarks", newValue) } }
    var marks: [MarkDefinition] { get { cod("rs.marks", MarkDefinition.defaults) } set { setCod("rs.marks", newValue) } }

    // 5 – Export & Dateien
    var defaultExportAction: DefaultExportAction { get { en("rs.defaultExportAction", .copy) } set { setEnum("rs.defaultExportAction", newValue) } }
    var exportSubfolders: Bool { get { b("rs.exportSubfolders", true) } set { set("rs.exportSubfolders", newValue) } }
    var useMarkFolderNames: Bool { get { b("rs.useMarkFolderNames", true) } set { set("rs.useMarkFolderNames", newValue) } }
    var exportFolderFormat: ExportFolderFormat { get { en("rs.exportFolderFormat", .numberName) } set { setEnum("rs.exportFolderFormat", newValue) } }
    var ignoreUnmarked: Bool { get { b("rs.ignoreUnmarked", true) } set { set("rs.ignoreUnmarked", newValue) } }
    var revealAfterExport: Bool { get { b("rs.revealAfterExport", true) } set { set("rs.revealAfterExport", newValue) } }
    var rememberExportTarget: Bool { get { b("rs.rememberExportTarget", true) } set { set("rs.rememberExportTarget", newValue) } }
    var detectRawJpgPairs: Bool { get { b("rs.detectRawJpgPairs", true) } set { set("rs.detectRawJpgPairs", newValue) } }
    var rawJpgExport: RawJpgExport { get { en("rs.rawJpgExport", .both) } set { setEnum("rs.rawJpgExport", newValue) } }
    var rawJpgOpen: RawJpgOpen { get { en("rs.rawJpgOpen", .raw) } set { setEnum("rs.rawJpgOpen", newValue) } }
    var conflictMode: ConflictMode { get { en("rs.conflictMode", .rename) } set { setEnum("rs.conflictMode", newValue) } }
    var keepFileDates: Bool { get { b("rs.keepFileDates", true) } set { set("rs.keepFileDates", newValue) } }
    var renameOnExport: Bool { get { b("rs.renameOnExport", false) } set { set("rs.renameOnExport", newValue) } }
    var allowMoveFromSD: Bool { get { b("rs.allowMoveFromSD", false) } set { set("rs.allowMoveFromSD", newValue) } }
    var allowDeleteFromSD: Bool { get { b("rs.allowDeleteFromSD", false) } set { set("rs.allowDeleteFromSD", newValue) } }
    var warnBeforeMove: Bool { get { b("rs.warnBeforeMove", true) } set { set("rs.warnBeforeMove", newValue) } }
    var warnBeforeDelete: Bool { get { b("rs.warnBeforeDelete", true) } set { set("rs.warnBeforeDelete", newValue) } }
    var deleteToTrashOnly: Bool { get { b("rs.deleteToTrashOnly", true) } set { set("rs.deleteToTrashOnly", newValue) } }

    // 6 – Performance & Cache
    var preloadPerfect: Bool { get { b("rs.preloadPerfect", true) } set { set("rs.preloadPerfect", newValue) } }
    var preloadForward: Double { get { dbl("rs.preloadForward", 20) } set { set("rs.preloadForward", newValue) } }
    var preloadBackward: Double { get { dbl("rs.preloadBackward", 10) } set { set("rs.preloadBackward", newValue) } }
    var preloadCurrentFilterOnly: Bool { get { b("rs.preloadCurrentFilterOnly", true) } set { set("rs.preloadCurrentFilterOnly", newValue) } }
    var cancelStalePreloads: Bool { get { b("rs.cancelStalePreloads", true) } set { set("rs.cancelStalePreloads", newValue) } }
    var maxParallelJobs: Double { get { dbl("rs.maxParallelJobs", 3) } set { set("rs.maxParallelJobs", newValue) } }
    var thumbnailCache: Bool { get { b("rs.thumbnailCache", true) } set { set("rs.thumbnailCache", newValue) } }
    var perfectCache: Bool { get { b("rs.perfectCache", true) } set { set("rs.perfectCache", newValue) } }
    var cachePath: String { get { str("rs.cachePath", "") } set { set("rs.cachePath", newValue) } }
    var cacheLimit: CacheLimit { get { en("rs.cacheLimit", .gb5) } set { setEnum("rs.cacheLimit", newValue) } }
    var autoCleanCache: Bool { get { b("rs.autoCleanCache", true) } set { set("rs.autoCleanCache", newValue) } }
    var cacheAge: CacheAge { get { en("rs.cacheAge", .d30) } set { setEnum("rs.cacheAge", newValue) } }
    var clearCacheOnQuit: Bool { get { b("rs.clearCacheOnQuit", false) } set { set("rs.clearCacheOnQuit", newValue) } }
    var autoManageMemory: Bool { get { b("rs.autoManageMemory", true) } set { set("rs.autoManageMemory", newValue) } }
    var reducePreloadLowPower: Bool { get { b("rs.reducePreloadLowPower", true) } set { set("rs.reducePreloadLowPower", newValue) } }

    // 7 – Darstellung
    var appearance: AppearanceMode { get { en("rs.appearance", .system) } set { setEnum("rs.appearance", newValue) } }
    var appBackground: AppBackground { get { en("rs.appBackground", .system) } set { setEnum("rs.appBackground", newValue) } }
    var previewBackground: PreviewBackground { get { en("rs.previewBackground", .system) } set { setEnum("rs.previewBackground", newValue) } }
    var accent: AccentChoice { get { en("rs.accent", .system) } set { setEnum("rs.accent", newValue) } }
    var accentCustomHex: String { get { str("rs.accentCustomHex", "#3B82F6") } set { set("rs.accentCustomHex", newValue) } }
    var colorMgmtThumbs: Bool { get { b("rs.colorMgmtThumbs", true) } set { set("rs.colorMgmtThumbs", newValue) } }
    var colorMgmtPreview: Bool { get { b("rs.colorMgmtPreview", true) } set { set("rs.colorMgmtPreview", newValue) } }
    var checkerboardTransparency: Bool { get { b("rs.checkerboardTransparency", true) } set { set("rs.checkerboardTransparency", newValue) } }
    var reduceMotion: Bool { get { b("rs.reduceMotion", true) } set { set("rs.reduceMotion", newValue) } }
    var subtleTransitions: Bool { get { b("rs.subtleTransitions", true) } set { set("rs.subtleTransitions", newValue) } }
    var metadataPanel: Bool { get { b("rs.metadataPanel", true) } set { set("rs.metadataPanel", newValue) } }
    var compactToolbar: Bool { get { b("rs.compactToolbar", true) } set { set("rs.compactToolbar", newValue) } }

    // 8 – Erweitert
    var externalAppPath: String { get { str("rs.externalAppPath", "") } set { set("rs.externalAppPath", newValue) } }
    var maxExternalOpen: Double { get { dbl("rs.maxExternalOpen", 20) } set { set("rs.maxExternalOpen", newValue) } }
    var warnManyExternal: Bool { get { b("rs.warnManyExternal", true) } set { set("rs.warnManyExternal", newValue) } }
    var xmpExport: Bool { get { b("rs.xmpExport", false) } set { set("rs.xmpExport", newValue) } }
    var writeMetadataJpeg: Bool { get { b("rs.writeMetadataJpeg", false) } set { set("rs.writeMetadataJpeg", newValue) } }
    var sessionLocation: SessionLocation { get { en("rs.sessionLocation", .appStorage) } set { setEnum("rs.sessionLocation", newValue) } }
    var debugLogs: Bool { get { b("rs.debugLogs", false) } set { set("rs.debugLogs", newValue) } }

    // MARK: Derived helpers
    func markDefinition(_ n: Int) -> MarkDefinition {
        marks.first { $0.id == n } ?? MarkDefinition.defaults[max(0, min(8, n - 1))]
    }
    func markColor(_ n: Int) -> Color { markDefinition(n).color }
    func markName(_ n: Int) -> String { markDefinition(n).name }

    /// Subfolder name for a mark on export, or nil to place in the target root.
    func exportFolderName(for mark: Int) -> String? {
        guard exportSubfolders, mark >= 1, mark <= 9 else { return nil }
        switch exportFolderFormat {
        case .single: return nil
        case .numberMark: return String(format: "%02d_Mark_%d", mark, mark)
        case .name: return useMarkFolderNames ? sanitize(markName(mark)) : String(format: "%02d", mark)
        case .numberName:
            let base = useMarkFolderNames ? markName(mark) : "Mark_\(mark)"
            return String(format: "%02d_", mark) + sanitize(base)
        }
    }
    private func sanitize(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }

    var accentColor: Color? {
        switch accent {
        case .system: return nil
        case .blue: return .blue
        case .graphite: return Color(white: 0.4)
        case .custom: return Color(hex: accentCustomHex)
        }
    }

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
