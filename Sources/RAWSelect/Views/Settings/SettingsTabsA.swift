import SwiftUI

// MARK: - 1. Allgemein

struct GeneralSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section("Darstellung") {
                SettingPicker(title: "Erscheinungsbild",
                              help: "Hell, Dunkel oder dem System folgen.",
                              selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 2. Ansicht & Performance (kurz: „Ansicht“)

struct ViewSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingSlider(title: "Thumbnail-Grösse",
                              help: "Grösse der Kacheln im Raster. Auch unten in der Statusleiste direkt einstellbar.",
                              value: $settings.thumbnailSize, range: 90...320) { "\(Int($0)) px" }
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
}
