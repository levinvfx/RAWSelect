import SwiftUI
import AppKit

// MARK: - 4. Markierungen

struct MarkSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingToggle(title: "Nach Markierung zum nächsten Bild springen",
                              help: "Perfekt fürs schnelle Sichten.",
                              isOn: $settings.autoAdvance)
            }
            Section("Markierungen 1–9") {
                ForEach($settings.marks) { $mark in
                    MarkEditorRow(mark: $mark)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MarkEditorRow: View {
    @Binding var mark: MarkDefinition
    var body: some View {
        HStack(spacing: 10) {
            Text("\(mark.id)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 14)
            ColorPicker("", selection: Binding(
                get: { mark.color },
                set: { mark.colorHex = $0.hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            TextField("Name", text: $mark.name).textFieldStyle(.roundedBorder)
            Button {
                if let d = MarkDefinition.defaults.first(where: { $0.id == mark.id }) { mark = d }
            } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.borderless)
            .help("Zurücksetzen")
        }
    }
}

// MARK: - 5. Export

struct ExportSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingToggle(title: "Nach Export Zielordner im Finder öffnen", isOn: $settings.revealAfterExport)
                SettingPicker(title: "RAW+JPG beim Export", selection: $settings.rawJpgExport) {
                    ForEach(RawJpgExport.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Photoshop-Export (experimentell)") {
                SettingToggle(title: "Export mit Photoshop aktivieren", isOn: $settings.photoshopExport)
                SettingPicker(title: "JPEG-Qualität", selection: $settings.jpegQuality) {
                    ForEach(JPEGQuality.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.photoshopExport)
                SettingPicker(title: "Smart Exposure", selection: $settings.smartExposure) {
                    ForEach(SmartExposure.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.photoshopExport)
                SettingPicker(title: "Maximale Helligkeitskorrektur", selection: $settings.smartExposureMax) {
                    ForEach(SmartExposureEV.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.photoshopExport || settings.smartExposure == .off)
                SettingPicker(title: "Farbraum", selection: $settings.colorSpace) {
                    ForEach(ColorSpaceChoice.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.photoshopExport)
                SettingToggle(title: "Highlights schützen", isOn: $settings.protectHighlights)
                SettingToggle(title: "Schatten schützen", isOn: $settings.protectShadows)
                SettingToggle(title: "Korrektur vor Export anzeigen", isOn: $settings.showCorrectionBeforeExport)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 6. Erweitert

struct AdvancedSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var confirmReset = false
    @State private var confirmClear = false
    @State private var status = ""

    private var photoshopLabel: String {
        settings.photoshopPath.isEmpty ? "Automatisch" : (settings.photoshopPath as NSString).lastPathComponent
    }
    private var presetLabel: String {
        settings.presetPath.isEmpty ? "Keins gewählt" : (settings.presetPath as NSString).lastPathComponent
    }

    var body: some View {
        Form {
            Section("Photoshop") {
                SettingToggle(title: "Photoshop automatisch finden", isOn: $settings.photoshopAutoDetect)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photoshop"); Text(photoshopLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manuell auswählen…") { choosePhotoshop() }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Standard-Preset (.xmp)"); Text(presetLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Auswählen…") { choosePreset() }
                }
                SettingToggle(title: "Photoshop nach Export schliessen", isOn: $settings.closePhotoshopAfter)
                SettingToggle(title: "Temporäre Dateien nach Export löschen", isOn: $settings.deleteTempFiles)
            }
            Section {
                Button("Cache leeren") { confirmClear = true }
                    .confirmationDialog("Cache leeren?", isPresented: $confirmClear) {
                        Button("Leeren", role: .destructive) { ThumbnailLoader.shared.clearCache(); status = "Cache geleert." }
                        Button("Abbrechen", role: .cancel) {}
                    }
                Button("Alle Einstellungen zurücksetzen…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Alle Einstellungen zurücksetzen?", isPresented: $confirmReset) {
                        Button("Zurücksetzen", role: .destructive) { settings.resetAll(); status = "Auf Standard zurückgesetzt." }
                        Button("Abbrechen", role: .cancel) {}
                    } message: { Text("Setzt alle Einstellungen auf die Standardwerte zurück.") }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private func choosePhotoshop() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { settings.photoshopPath = url.path }
    }
    private func choosePreset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { settings.presetPath = url.path }
    }
}
