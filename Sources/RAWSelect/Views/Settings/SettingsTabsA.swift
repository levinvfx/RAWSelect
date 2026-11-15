import SwiftUI

// MARK: - 1. Ansicht

struct ViewSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingToggle(title: L("RAW+JPG als ein Bild anzeigen"),
                              help: L("Fasst z. B. DSC0123.ARW und DSC0123.JPG zusammen. Wirkt beim nächsten Öffnen eines Ordners."),
                              isOn: $settings.groupRawJpg)
                SettingPicker(title: L("Vorschau-Modus"),
                              help: L("Steuert Schärfe und Vorausladen der Vorschau. „Ausgewogen“ passt für die meisten."),
                              selection: $settings.previewMode) {
                    ForEach(PreviewMode.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Text("Thumbnail-Grösse und Sortierung stellst du direkt im Hauptfenster ein (Statusleiste bzw. Symbolleiste).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
