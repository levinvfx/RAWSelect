import SwiftUI
import AppKit

// MARK: - 5. Export & Dateien

struct ExportSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section("Export") {
                SettingPicker(title: "Standardaktion", selection: $settings.defaultExportAction) {
                    ForEach(DefaultExportAction.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Beim Export Unterordner pro Markierung erstellen", isOn: $settings.exportSubfolders)
                SettingToggle(title: "Ordnernamen der Markierungen verwenden", isOn: $settings.useMarkFolderNames)
                SettingPicker(title: "Export-Ordnerformat", selection: $settings.exportFolderFormat) {
                    ForEach(ExportFolderFormat.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Unmarkierte Bilder ignorieren", isOn: $settings.ignoreUnmarked)
                SettingToggle(title: "Nach Export Zielordner im Finder öffnen", isOn: $settings.revealAfterExport)
                SettingToggle(title: "Letzten Export-Zielordner merken", isOn: $settings.rememberExportTarget)
            }
            Section("RAW+JPG") {
                SettingToggle(title: "RAW+JPG-Paare erkennen", isOn: $settings.detectRawJpgPairs)
                SettingPicker(title: "Beim Export von RAW+JPG-Paaren", selection: $settings.rawJpgExport) {
                    ForEach(RawJpgExport.allCases) { Text($0.label).tag($0) }
                }
                SettingPicker(title: "Beim externen Öffnen von RAW+JPG-Paaren", selection: $settings.rawJpgOpen) {
                    ForEach(RawJpgOpen.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Dateikonflikte") {
                SettingPicker(title: "Wenn Datei im Ziel bereits existiert", help: "Überschreiben nur mit zusätzlicher Warnung.", selection: $settings.conflictMode) {
                    ForEach(ConflictMode.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Original-Erstellungs- und Änderungsdatum behalten", isOn: $settings.keepFileDates)
                SettingToggle(title: "Dateinamen beim Export verändern", help: "Für V1 bleiben Original-Dateinamen standardmässig erhalten.", isOn: $settings.renameOnExport)
            }
            Section("Löschen / Verschieben") {
                SettingToggle(title: "Von SD-Karten verschieben erlauben", help: "⚠︎ Bewegt Originale von der Karte. Standardmässig aus, um Originale zu schützen.", isOn: $settings.allowMoveFromSD)
                SettingToggle(title: "Von SD-Karten löschen erlauben", help: "⚠︎ In V1 nicht empfohlen. RAW Select löscht keine Originale von Karten.", isOn: $settings.allowDeleteFromSD)
                SettingToggle(title: "Vor Verschieben immer warnen", isOn: $settings.warnBeforeMove)
                SettingToggle(title: "Vor Löschen immer warnen", isOn: $settings.warnBeforeDelete)
                SettingToggle(title: "Löschen nur in Papierkorb", help: "RAW Select löscht keine Dateien dauerhaft.", isOn: $settings.deleteToTrashOnly)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 6. Performance & Cache

struct PerformanceSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var confirmClear = false

    private var cacheDisplay: String {
        settings.cachePath.isEmpty ? "~/Library/Caches/RAW Select" : settings.cachePath
    }

    var body: some View {
        Form {
            Section("Preview-Preloading") {
                SettingToggle(title: "Perfect Previews vorausladen", help: "Lädt hochwertige Vorschauen rund um die Auswahl im Hintergrund vor.", isOn: $settings.preloadPerfect)
                stepperRow(title: "Anzahl Bilder vorausladen", value: $settings.preloadForward, range: 1...50)
                stepperRow(title: "Anzahl Bilder rückwärts vorausladen", value: $settings.preloadBackward, range: 1...50)
                SettingToggle(title: "Nur aktuellen Filter vorausladen", isOn: $settings.preloadCurrentFilterOnly)
                SettingToggle(title: "Alte Preload-Jobs bei schnellem Springen abbrechen", isOn: $settings.cancelStalePreloads)
                stepperRow(title: "Maximale parallele Preview-Jobs", value: $settings.maxParallelJobs, range: 1...8)
            }
            Section("Cache") {
                SettingToggle(title: "Thumbnail-Cache aktivieren", isOn: $settings.thumbnailCache)
                SettingToggle(title: "Perfect-Preview-Cache aktivieren", isOn: $settings.perfectCache)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cache-Speicherort")
                        Text(cacheDisplay).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Ändern…") { chooseCachePath() }
                    Button("Standard") { settings.cachePath = "" }
                }
                SettingPicker(title: "Disk-Cache-Grösse", selection: $settings.cacheLimit) {
                    ForEach(CacheLimit.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Cache automatisch bereinigen", isOn: $settings.autoCleanCache)
                SettingPicker(title: "Cache-Alter", selection: $settings.cacheAge) {
                    ForEach(CacheAge.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Cache beim Beenden löschen", help: "Normalerweise auslassen, sonst wird die App wieder langsamer.", isOn: $settings.clearCacheOnQuit)
                Button("Cache jetzt leeren") { confirmClear = true }
                    .confirmationDialog("Cache leeren?", isPresented: $confirmClear) {
                        Button("Cache leeren", role: .destructive) { ThumbnailLoader.shared.clearCache() }
                        Button("Abbrechen", role: .cancel) {}
                    } message: { Text("Leert Thumbnail- und Preview-Cache. Bilder werden bei Bedarf neu geladen.") }
            }
            Section {
                SettingToggle(title: "Speicher automatisch verwalten", help: "RAW Select begrenzt den RAM-Verbrauch automatisch.", isOn: $settings.autoManageMemory)
                SettingToggle(title: "Preloading im Energiesparmodus reduzieren", help: "Reduziert Hintergrundarbeit im macOS Low Power Mode.", isOn: $settings.reducePreloadLowPower)
            }
        }
        .formStyle(.grouped)
    }

    private func stepperRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.wrappedValue))").monospacedDigit().foregroundStyle(.secondary)
            Stepper("", value: value, in: range, step: 1).labelsHidden()
        }
    }

    private func chooseCachePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Wählen"
        if panel.runModal() == .OK, let url = panel.url { settings.cachePath = url.path }
    }
}

// MARK: - 7. Darstellung

struct AppearanceSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingPicker(title: "Erscheinungsbild", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                SettingPicker(title: "App-Hintergrund", selection: $settings.appBackground) {
                    ForEach(AppBackground.allCases) { Text($0.label).tag($0) }
                }
                SettingPicker(title: "Preview-Hintergrund", selection: $settings.previewBackground) {
                    ForEach(PreviewBackground.allCases) { Text($0.label).tag($0) }
                }
                SettingPicker(title: "Akzentfarbe", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { Text($0.label).tag($0) }
                }
                if settings.accent == .custom {
                    ColorPicker("Eigene Akzentfarbe", selection: Binding(
                        get: { Color(hex: settings.accentCustomHex) },
                        set: { settings.accentCustomHex = $0.hexString }), supportsOpacity: false)
                }
            }
            Section {
                SettingToggle(title: "Color Management für Thumbnails", help: "Vorschaubilder farblich möglichst korrekt.", isOn: $settings.colorMgmtThumbs)
                SettingToggle(title: "Color Management für Previews", help: "Grosse Preview farblich möglichst korrekt.", isOn: $settings.colorMgmtPreview)
                SettingToggle(title: "Transparente Bilder mit Checkerboard anzeigen", isOn: $settings.checkerboardTransparency)
            }
            Section {
                SettingToggle(title: "Animationen reduzieren, wenn macOS es vorgibt", help: "Respektiert die Bedienungshilfen.", isOn: $settings.reduceMotion)
                SettingToggle(title: "Dezente Übergänge beim Bildwechsel", isOn: $settings.subtleTransitions)
                SettingToggle(title: "Metadaten-Panel anzeigen", help: "Kamera, Objektiv, Brennweite, Blende, Zeit, ISO, Datum.", isOn: $settings.metadataPanel)
                SettingToggle(title: "Kompakte Toolbar verwenden", isOn: $settings.compactToolbar)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 8. Erweitert

struct AdvancedSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var confirmReset = false
    @State private var statusText = ""

    private var externalDisplay: String {
        settings.externalAppPath.isEmpty ? "Systemstandard" : (settings.externalAppPath as NSString).lastPathComponent
    }

    var body: some View {
        Form {
            Section("Externe Programme") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Standard-App zum externen Öffnen")
                        Text(externalDisplay).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Wählen…") { chooseApp() }
                    Button("Systemstandard") { settings.externalAppPath = "" }
                }
                HStack {
                    Text("Maximal gleichzeitig extern öffnen"); Spacer()
                    Text("\(Int(settings.maxExternalOpen))").monospacedDigit().foregroundStyle(.secondary)
                    Stepper("", value: $settings.maxExternalOpen, in: 1...100).labelsHidden()
                }
                SettingToggle(title: "Warnen bei sehr vielen extern geöffneten Bildern", isOn: $settings.warnManyExternal)
            }
            Section("XMP / Metadaten") {
                SettingToggle(title: "XMP-Sidecar-Export aktivieren", help: "Experimentell: kann Markierungen später als .xmp-Dateien exportieren.", isOn: $settings.xmpExport)
                SettingToggle(title: "Original-RAW-Dateien verändern", help: "RAW Select verändert keine Original-RAW-Dateien.", isOn: .constant(false), disabled: true)
                SettingToggle(title: "Metadaten in JPEG schreiben", help: "Für V1 aus. RAW Select bleibt nicht-destruktiv.", isOn: $settings.writeMetadataJpeg)
            }
            Section("Session") {
                SettingPicker(title: "Session-Speicherort", help: "App-Speicher hält Bildordner sauber. Sidecar ist praktisch für andere Macs.", selection: $settings.sessionLocation) {
                    ForEach(SessionLocation.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Button("Session-Daten exportieren…") { exportSessions() }
                    Button("Session-Daten importieren…") { importSessions() }
                }
            }
            Section("Debug / Wartung") {
                SettingToggle(title: "Debug Logs aktivieren", isOn: $settings.debugLogs)
                HStack {
                    Button("Log-Datei anzeigen") { revealLogLocation() }
                    Button("Alle Warnhinweise zurücksetzen") { resetWarnings() }
                }
                Button("Alle Settings zurücksetzen…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Alle Settings zurücksetzen?", isPresented: $confirmReset) {
                        Button("Zurücksetzen", role: .destructive) { settings.resetAll() }
                        Button("Abbrechen", role: .cancel) {}
                    } message: { Text("Setzt alle Einstellungen auf die Standardwerte zurück.") }
                if !statusText.isEmpty {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { settings.externalAppPath = url.path }
    }

    private func exportSessions() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "RAWSelect-Sessions.json"
        if panel.runModal() == .OK, let url = panel.url {
            statusText = SessionStore.exportAll(to: url) ? "Sessions exportiert." : "Export fehlgeschlagen."
        }
    }
    private func importSessions() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            statusText = SessionStore.importAll(from: url) ? "Sessions importiert." : "Import fehlgeschlagen."
        }
    }
    private func revealLogLocation() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RAW Select", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
    private func resetWarnings() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("rs.warnSuppress.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        statusText = "Warnhinweise zurückgesetzt."
    }
}
