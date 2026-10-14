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
            Section("Markierungen · Tasten 1–7") {
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
    private var isDefault: Bool { MarkDefinition.defaults.first { $0.id == mark.id } == mark }
    var body: some View {
        HStack(spacing: 10) {
            // Live preview: exactly the badge the grid and the filter bar will show.
            MarkBadge(mark: mark.id, size: 16)
                .frame(width: 22)
            TextField("", text: $mark.name, prompt: Text("Name"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            ColorPicker("", selection: Binding(
                get: { mark.color },
                set: { mark.colorHex = $0.hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Farbe")
            Button {
                if let d = MarkDefinition.defaults.first(where: { $0.id == mark.id }) { mark = d }
            } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.borderless)
            .disabled(isDefault)
            .help("Auf Standard zurücksetzen")
        }
    }
}

#if DEBUG
// MARK: - 5. Export (development builds only)

struct ExportSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section("JPEG-Export mit Preset") {
                Text("Lightroom Classic rendert die JPEGs und wendet Preset-Masken (KI-Motiv, Verläufe) an. Lightroom wird beim Export automatisch gestartet und muss das Plugin „RAW Select Bridge“ geladen haben.")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("JPEG-Qualität"); Spacer(); Text("\(Int(settings.jpegQualityPercent))%").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: $settings.jpegQualityPercent, in: 10...100, step: 10)
                }
                SettingPicker(title: "Farbraum", selection: $settings.colorSpace) {
                    ForEach(ColorSpaceChoice.allCases) { Text($0.label).tag($0) }
                }
                Text("Die Helligkeit stellst du beim Export pro Bild manuell im „Zuschneiden & Belichten“-Schritt ein (wie in Lightroom, −5…+5).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lightroom") {
                SettingToggle(title: "KI-Dialoge automatisch bestätigen",
                              help: "Klickt Lightrooms Nachfragen (Motiv-Modell aktualisieren, KI-Entrauschen/„Verbessern“) beim Export automatisch weg. Benötigt einmalig die Bedienungshilfen-Berechtigung.",
                              isOn: $settings.autoConfirmLightroomDialogs)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 6. Erweitert

#endif

struct AdvancedSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var confirmReset = false
    @State private var confirmClear = false
    @State private var status = ""

    #if DEBUG
    private var presetLabel: String {
        settings.presetPath.isEmpty ? "Keins gewählt" : (settings.presetPath as NSString).lastPathComponent
    }
    private var lightroomLabel: String {
        settings.lightroomPath.isEmpty ? "Automatisch" : (settings.lightroomPath as NSString).lastPathComponent
    }
    #endif
    private var openWithLabel: String {
        settings.openWithAppPath.isEmpty ? "Beim ersten Klick wählen" : OpenWithService.appName(settings.openWithAppPath)
    }

    var body: some View {
        Form {
            Section("Darstellung") {
                SettingPicker(title: "Erscheinungsbild",
                              help: "Hell, Dunkel oder dem System folgen.",
                              selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Kopieren") {
                SettingToggle(title: "Nach dem Kopieren Zielordner im Finder zeigen", isOn: $settings.revealAfterExport)
            }
            Section("Nutzungszählung") {
                Text("RAW Select meldet beim Start höchstens einmal täglich eine zufällige Kennung, die App-Version und die macOS-Version an vfxmedia.ch – so ist sichtbar, wie viele Leute die App nutzen. Keine Dateien, keine Namen, kein Standort, keine IP-Adresse.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deine Kennung")
                        Text(TelemetryService.installationID)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Kopieren") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(TelemetryService.installationID, forType: .string)
                        status = "Kennung kopiert."
                    }
                }
                HStack(spacing: 16) {
                    Link("Löschung meiner Daten verlangen", destination: TelemetryService.deletionRequestURL)
                    Link("Datenschutzerklärung", destination: AppInfo.privacyURL)
                }
                .font(.caption)
            }
            Section("Bilder öffnen mit") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Öffnen-Button (Symbolleiste)")
                        Text(openWithLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Ändern…") {
                        ForEach(OpenWithService.lightroomApps(), id: \.self) { url in
                            Button(OpenWithService.appName(url.path)) { settings.openWithAppPath = url.path }
                        }
                        Divider()
                        Button("Andere App wählen…") {
                            if let u = OpenWithService.chooseApp() { settings.openWithAppPath = u.path }
                        }
                        if !settings.openWithAppPath.isEmpty {
                            Divider()
                            Button("Zurücksetzen") { settings.openWithAppPath = "" }
                        }
                    }
                    .frame(width: 130)
                }
                Text("Der Button in der Symbolleiste öffnet die ausgewählten Bilder in dieser App (z. B. Lightroom oder Lightroom Classic).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #if DEBUG
            Section("Lightroom Classic (Entwicklungs-Build)") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lightroom Classic"); Text(lightroomLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manuell auswählen…") { chooseLightroom() }
                }
                Text("Für den Masken-Export muss in Lightroom das Plugin „RAW Select Bridge“ installiert und aktiv sein (Datei → Zusatzmodul-Manager).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Standard-Preset (.xmp)"); Text(presetLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Auswählen…") { choosePreset() }
                }
                SettingToggle(title: "Temporäre Dateien nach Export löschen", isOn: $settings.deleteTempFiles)
            }
            #endif
            Section {
                Button("Cache leeren") { confirmClear = true }
                    .confirmationDialog("Cache leeren?", isPresented: $confirmClear) {
                        Button("Leeren", role: .destructive) {
                            ThumbnailLoader.shared.clearCache()
                            #if DEBUG
                            Task { await LightroomPreviewService.shared.clearCache() }
                            #endif
                            status = "Cache geleert."
                        }
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

    #if DEBUG
    private func chooseLightroom() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { settings.lightroomPath = url.path }
    }
    private func choosePreset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { settings.presetPath = url.path }
    }
    #endif
}
