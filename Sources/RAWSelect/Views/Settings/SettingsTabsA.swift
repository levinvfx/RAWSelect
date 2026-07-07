import SwiftUI

// MARK: - 1. Allgemein

struct GeneralSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingToggle(title: "Letzte Session wiederherstellen",
                              help: "Öffnet den zuletzt verwendeten Ordner samt Markierungen wieder.",
                              isOn: $settings.restoreSession)
                SettingToggle(title: "Warnen, wenn beim Beenden ein Vorgang läuft",
                              isOn: $settings.warnOnQuitDuringOp)
                SettingToggle(title: "Abschluss-Benachrichtigung anzeigen",
                              help: "Kurze Meldung, wenn Kopieren oder Verschieben fertig ist.",
                              isOn: $settings.completionNotification)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 2. Quellen

struct SourcesSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingToggle(title: "SD-Karten automatisch erkennen",
                              help: "Erkennt neu angeschlossene Kameras und Karten.",
                              isOn: $settings.autoDetectVolumes)
                SettingPicker(title: "Bei erkannter SD-Karte",
                              selection: $settings.sdBehavior) {
                    ForEach(SDBehavior.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.autoDetectVolumes)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 3. Ansicht & Performance (kurz: „Ansicht“)

struct ViewSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Thumbnail-Grösse")
                        Spacer()
                        Text(sizeLabel).foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.thumbnailSize, in: 80...260, step: 4)
                }
                SettingPicker(title: "Sortieren nach", selection: $settings.sortField) {
                    ForEach(SortField.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Sortierung umkehren", isOn: $settings.sortReversed)
                SettingToggle(title: "RAW+JPG als ein Bild anzeigen",
                              help: "Fasst z. B. DSC0123.ARW und DSC0123.JPG zusammen.",
                              isOn: $settings.groupRawJpg)
            }
            Section {
                SettingPicker(title: "Vorschau-Modus",
                              help: "Steuert Schärfe und Vorausladen der Vorschau. „Ausgewogen“ passt für die meisten.",
                              selection: $settings.previewMode) {
                    ForEach(PreviewMode.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var sizeLabel: String {
        switch settings.thumbnailSize {
        case ..<115: return "Klein"
        case 115...170: return "Mittel"
        default: return "Gross"
        }
    }
}
